# Inspired by https://github.com/JamesTurland/JimsGarage/blob/main/Kubernetes/K3S-Deploy/k3s.sh

##############################
#         Define ENVs        #
##############################
# Kube-VIP Version
KVVERSION=$(curl -sL https://api.github.com/repos/kube-vip/kube-vip/releases | jq -r ".[0].name")
# K3S Version
k3sVersion="v1.28.9+k3s1"

# Set the IP addresses of the master and work nodes
master1=172.16.50.10
master2=172.16.50.11
master3=172.16.50.12
worker1=172.16.50.13
worker2=172.16.50.14

# User of remote machines
user=rene

# Interface used on remotes
interface=eth0

# Set the virtual IP address (VIP)
vip=192.168.50.20

# Array of master nodes
masters=($master2 $master3)

# Array of worker nodes
workers=($worker1 $worker2)

# Array of all
all=($master1 $master2 $master3 $worker1 $worker2)

# Array of all minus master
allnomaster1=($master2 $master3 $worker1 $worker2)

#Loadbalancer IP range
lbrange=172.16.50.70-172.16.50.99

#ssh certificate name variable
certName=id_ed25519_proxmox

##############################
#         Installation       #
##############################

# Move SSH certs to ~/.ssh and change permissions
cp /home/$user/{$certName,$certName.pub} /home/$user/.ssh
chmod 600 /home/$user/.ssh/$certName 
chmod 644 /home/$user/.ssh/$certName.pub

# Install k3sup to local machine if not already present
if ! command -v k3sup version &> /dev/null
then
    echo -e " \033[32;49mk3sup not found, installing...\033[0m"
    curl -sLS https://get.k3sup.dev | sh
    sudo install k3sup /usr/local/bin/
    echo -e " \033[32;49mk3sup installed successfully\033[0m"
else
    echo -e " \033[31;49mk3sup already installed\033[0m"
fi

# Install Kubectl if not already present
if ! command -v kubectl version &> /dev/null
then
    echo -e " \033[32;49mKubectl not found, installing...\033[0m"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    echo -e " \033[32;49mKubectl installed successfully\033[0m"
else
    echo -e " \033[31;49mKubectl already installed\033[0m"
fi

# Create SSH Config file to ignore checking (don't use in production!)
echo -e " \033[32;49mCreate SSH Config file to ignore checking\033[0m"
echo -e "StrictHostKeyChecking no\n" > ~/.ssh/config

#add ssh keys for all nodes
echo -e " \033[32;49mAdding SSH Key for each node...\033[0m"
for node in "${all[@]}"; do
  ssh-copy-id $user@$node
done
 echo -e " \033[32;49mSuccessfully added SSH Keys\033[0m"

# Install policycoreutils for each node
echo -e " \033[32;49mInstall policycoreutils for each node...\033[0m"
for newnode in "${all[@]}"; do
  ssh $user@$newnode -i ~/.ssh/$certName sudo su <<EOF
  NEEDRESTART_MODE=a apt install policycoreutils -y
  exit
EOF
done
echo -e " \033[32;49mPolicyCoreUtils installed successfully!\033[0m"

# Step 1: Bootstrap First k3s Node
echo -e " \033[32;49mBootstraping First k3s Node...\033[0m"
mkdir ~/.kube
k3sup install \
  --ip $master1 \
  --user $user \
  --tls-san $vip \
  --cluster \
  --k3s-version $k3sVersion \
  --k3s-extra-args "--disable traefik --disable servicelb --flannel-iface=$interface --node-ip=$master1 --node-taint node-role.kubernetes.io/master=true:NoSchedule" \
  --merge \
  --sudo \
  --local-path $HOME/.kube/config \
  --ssh-key $HOME/.ssh/$certName \
  --context k3s-ha
echo -e " \033[32;49mFirst Node bootstrapped successfully!\033[0m"

# Step 2: Install Kube-VIP for HA
echo -e " \033[32;49mInstalling Kube-VIP for HA...\033[0m"
kubectl apply -f https://kube-vip.io/manifests/rbac.yaml


# Step 3: Download kube-vip
echo -e " \033[32;49mEditing Kube-VIP DaemonSet for HA and uploading to Master Node...\033[0m"
curl -sO https://raw.githubusercontent.com/renekrieg/homelab/main/Kubernetes/K3s/kube-vip-daemon.yaml
cat kube-vip | sed 's/$interface/'$interface'/g; s/$vip/'$vip'/g' > $HOME/kube-vip.yaml

# Step 4: Copy kube-vip.yaml to master1
scp -i ~/.ssh/$certName $HOME/kube-vip.yaml $user@$master1:~/kube-vip.yaml

# Step 5: Connect to Master1 and move kube-vip.yaml
ssh $user@$master1 -i ~/.ssh/$certName <<- EOF
  sudo mkdir -p /var/lib/rancher/k3s/server/manifests
  sudo mv kube-vip.yaml /var/lib/rancher/k3s/server/manifests/kube-vip.yaml
EOF
echo -e " \033[32;49mKube-VIP DaemonSet uploaded successfully\033[0m"

# Step 6: Add new master nodes (servers) & workers
echo -e " \033[32;49mAdding new master nodes (servers)...\033[0m"
for newnode in "${masters[@]}"; do
  k3sup join \
    --ip $newnode \
    --user $user \
    --sudo \
    --k3s-version $k3sVersion \
    --server \
    --server-ip $master1 \
    --ssh-key $HOME/.ssh/$certName \
    --k3s-extra-args "--disable traefik --disable servicelb --flannel-iface=$interface --node-ip=$newnode --node-taint node-role.kubernetes.io/master=true:NoSchedule" \
    --server-user $user
  echo -e " \033[32;49mMaster node joined successfully!\033[0m"
done
echo -e " \033[32;49mAll Master nodes joined successfully!\033[0m"

# add workers
echo -e " \033[32;49mAdding new Agent nodes...\033[0m"
for newagent in "${workers[@]}"; do
  k3sup join \
    --ip $newagent \
    --user $user \
    --sudo \
    --k3s-version $k3sVersion \
    --server-ip $master1 \
    --ssh-key $HOME/.ssh/$certName \
    --k3s-extra-args "--node-label \"longhorn=true\" --node-label \"worker=true\""
  echo -e " \033[32;49mAgent node joined successfully!\033[0m"
done
echo -e " \033[32;49mAll Agent nodes joined successfully!\033[0m"

# Step 7: Install kube-vip as network LoadBalancer - Install the kube-vip Cloud Provider
echo -e " \033[32;49mInstalling  kube-vip as network LoadBalancer...\033[0m"
kubectl apply -f https://raw.githubusercontent.com/kube-vip/kube-vip-cloud-provider/main/manifest/kube-vip-cloud-controller.yaml

# Step 8: Install Metallb
echo -e " \033[32;49mInstalling  Metallb...\033[0m"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
# Download ipAddressPool and configure using lbrange above
echo -e " \033[32;49mDownloading  ipAddressPool and configuring using lbrange...\033[0m"
curl -sO https://raw.githubusercontent.com/renekrieg/homelab/main/Kubernetes/K3s/ipAddressPool
cat ipAddressPool | sed 's/$lbrange/'$lbrange'/g' > $HOME/ipAddressPool.yaml
kubectl apply -f $HOME/ipAddressPool.yaml

# Step 9: Test with Nginx
echo -e " \033[32;49mValidating installation with Nginx...\033[0m"
kubectl apply -f https://raw.githubusercontent.com/inlets/inlets-operator/master/contrib/nginx-sample-deployment.yaml -n default
kubectl expose deployment nginx-1 --port=80 --type=LoadBalancer -n default

echo -e " \033[32;49mWaiting for K3S to sync and LoadBalancer to come online\033[0m"

while [[ $(kubectl get pods -l app=nginx -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
   sleep 1
done

# Step 10: Deploy IP Pools and l2Advertisement
echo -e " \033[32;49mDeploying IP Pools and l2Advertisement...\033[0m"
kubectl wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=component=controller \
                --timeout=120s
kubectl apply -f ipAddressPool.yaml
kubectl apply -f https://raw.githubusercontent.com/renekrieg/homelab/main/Kubernetes/K3s/l2Advertisement.yaml

kubectl get nodes
kubectl get svc
kubectl get pods --all-namespaces -o wide

echo -e " \033[32;5mDONE! Access Nginx at EXTERNAL-IP above\033[0m"
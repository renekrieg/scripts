import argparse
import os
import shutil

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--name", help="Name after which the project is to be designated")
  parser.add_argument("--path", help="Path where the project is to be saved")
  args = parser.parse_args()
  project_name = args.name
  project_path = args.path

  def create():
    templates = os.path.join(os.getcwd() + "/ressources")
    os.chdir(project_path)
    root = project_name
    src = os.path.join(root + "/src")
    ressources = os.path.join(src + "/ressources")
    main = os.path.join(src + "/main.py")
    init = os.path.join(src + "/__init__.py")
    tests = os.path.join(root + "/tests")
    test_main = os.path.join(tests + "/main.py")
    test_init = os.path.join(tests + "/__init__.py")
    req = os.path.join(root + "/requirements.txt")

    os.mkdir(project_name)
    os.mkdir(src)
    os.mkdir(ressources)
    open(main, 'x')
    open(init, 'x')
    os.mkdir(tests)
    open(test_main, 'x')
    open(test_init, 'x')
    open(req, 'x')
    shutil.copyfile(templates + "/README.md", root + "/README.md")
    shutil.copyfile(templates + "/LICENSE", root + "/LICENSE")
    
  if not os.path.isdir(project_name):
    create()
  else:
    print(f"Folder {project_name} already exists")

if __name__ == "__main__":
    main()
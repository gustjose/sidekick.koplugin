import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)

META_FILE = os.path.join(ROOT_DIR, "src", "_meta.lua")

def run_command(command):
    try:
        subprocess.check_call(command, shell=True, cwd=ROOT_DIR)
    except subprocess.CalledProcessError:
        print(f"❌ Erro ao executar: {command}")
        sys.exit(1)

def get_current_branch():
    result = subprocess.run("git rev-parse --abbrev-ref HEAD", shell=True, cwd=ROOT_DIR, capture_output=True, text=True)
    return result.stdout.strip()

def manage_version():
    if not os.path.exists(META_FILE):
        print(f"❌ Arquivo não encontrado: {META_FILE}")
        sys.exit(1)

    with open(META_FILE, 'r', encoding='utf-8') as f:
        content = f.read()

    match = re.search(r'version\s*=\s*"([^"]+)"', content)
    
    if not match:
        print("❌ Chave 'version' não encontrada no _meta.lua")
        sys.exit(1)

    current_version = match.group(1)
    print(f"📌 Versão Atual: {current_version}")
    
    new_version = input("👉 Nova versão (ex: 1.0.1): ").strip()
    
    if not new_version:
        sys.exit(0)

    if new_version.lower().startswith('v'):
        new_version = new_version[1:]

    new_content = re.sub(r'version\s*=\s*"[^"]+"', f'version = "{new_version}"', content)
    
    with open(META_FILE, 'w', encoding='utf-8') as f:
        f.write(new_content)
        
    print(f"✅ _meta.lua atualizado para {new_version}")
    return new_version

def git_operations(version):
    branch = get_current_branch()
    print(f"🔄 Git na branch '{branch}'...")

    run_command(f'git add "{META_FILE}"')
    run_command(f'git commit -m "Bump version to {version}"')
    run_command(f'git tag {version}')
    print(f"🏷️  Tag criada: {version}")

    print("☁️  Enviando para GitHub...")
    run_command(f'git push origin {branch}')
    run_command(f'git push origin {version}')
    
    print("\n🚀 Sucesso!")

if __name__ == "__main__":
    print("--- Sidekick Plugin Release ---")
    new_ver = manage_version()
    
    if input(f"Commitar, taggear '{new_ver}' e push? (s/n): ").lower() == 's':
        git_operations(new_ver)
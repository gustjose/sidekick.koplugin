import os
import re
import subprocess
import sys

# Caminhos relativos
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR) # Pasta sidekick.koplugin/
META_FILE = os.path.join(ROOT_DIR, "_meta.lua")

def run_command(command):
    """Executa um comando no shell e verifica erros."""
    try:
        subprocess.check_call(command, shell=True, cwd=ROOT_DIR)
    except subprocess.CalledProcessError as e:
        print(f"❌ Erro ao executar: {command}")
        sys.exit(1)

def get_current_branch():
    """Obtém o nome da branch atual."""
    result = subprocess.run("git rev-parse --abbrev-ref HEAD", shell=True, cwd=ROOT_DIR, capture_output=True, text=True)
    return result.stdout.strip()

def manage_version():
    # 1. Ler a versão atual do _meta.lua
    if not os.path.exists(META_FILE):
        print(f"❌ Arquivo não encontrado: {META_FILE}")
        sys.exit(1)

    with open(META_FILE, 'r', encoding='utf-8') as f:
        content = f.read()

    # Regex para encontrar: version = "1.0.0"
    match = re.search(r'version\s*=\s*"([^"]+)"', content)
    
    if not match:
        print("❌ Não foi possível encontrar a chave 'version' no _meta.lua")
        sys.exit(1)

    current_version = match.group(1)
    
    print(f"📌 Versão Atual: {current_version}")
    
    # 2. Solicitar nova versão
    new_version = input("👉 Digite a nova versão (ex: 1.0.1): ").strip()
    
    if not new_version:
        print("Operação cancelada.")
        sys.exit(0)

    # Verifica se o usuário colocou 'v' sem querer e avisa (mas remove se quiser forçar)
    if new_version.lower().startswith('v'):
        new_version = new_version[1:]
        print(f"⚠️  O prefixo 'v' foi removido. Usando: {new_version}")

    # 3. Atualizar o arquivo _meta.lua
    new_content = re.sub(r'version\s*=\s*"[^"]+"', f'version = "{new_version}"', content)
    
    with open(META_FILE, 'w', encoding='utf-8') as f:
        f.write(new_content)
        
    print(f"✅ _meta.lua atualizado para {new_version}")

    return new_version

def git_operations(version):
    branch = get_current_branch()
    print(f"🔄 Iniciando operações Git na branch '{branch}'...")

    # Git Add
    run_command(f'git add "{META_FILE}"')
    
    # Git Commit
    commit_msg = f"Bump version to {version}"
    run_command(f'git commit -m "{commit_msg}"')
    
    # Git Tag (Sem o prefixo 'v', conforme solicitado)
    run_command(f'git tag {version}')
    print(f"🏷️  Tag criada: {version}")

    # Git Push (Commits)
    print("☁️  Enviando alterações para o GitHub...")
    run_command(f'git push origin {branch}')
    
    # Git Push (Tags)
    run_command(f'git push origin {version}')
    
    print("\n🚀 Sucesso! Versão atualizada e sincronizada.")

if __name__ == "__main__":
    print("--- Sidekick Plugin Deploy ---")
    new_ver = manage_version()
    
    confirm = input(f"Deseja commitar, criar a tag '{new_ver}' e dar push? (s/n): ")
    if confirm.lower() == 's':
        git_operations(new_ver)
    else:
        print("Alterações feitas no arquivo, mas git cancelado.")
import subprocess
import os
import sys
import time
import signal

# --- CONFIGURAÇÕES ---
# Caminho do seu ADB (peguei do seu log anterior)
ADB_PATH = r"C:\Program Files\Android Tools\adb.exe"

# Pasta no Android onde o plugin fica
REMOTE_PATH = "/storage/emulated/0/koreader/plugins/sidekick.koplugin/"

# Arquivos que você quer copiar (adicione outros se precisar)
FILES_TO_SYNC = [
    "main.lua",
    "progress.lua",
    "_meta.lua",
    "utils.lua"
]

# Termo para filtrar no log
FILTER_KEYWORD = "Sidekick"

# --- CORES PARA O TERMINAL ---
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def run_command(command):
    """Roda um comando no shell e espera terminar"""
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"{Colors.FAIL}Erro ao executar: {command}{Colors.ENDC}")
        print(result.stderr)
        return False
    return True

def sync_files():
    print(f"{Colors.HEADER}--- 1. Copiando arquivos para o Android ---{Colors.ENDC}")
    
    # Verifica se o ADB existe
    if not os.path.exists(ADB_PATH):
        print(f"{Colors.FAIL}ERRO: ADB não encontrado em: {ADB_PATH}{Colors.ENDC}")
        sys.exit(1)

    for file in FILES_TO_SYNC:
        if os.path.exists(file):
            print(f"Enviando {Colors.OKBLUE}{file}{Colors.ENDC}...")
            # Comando: adb push arquivo destino
            cmd = f'"{ADB_PATH}" push "{file}" "{REMOTE_PATH}"'
            run_command(cmd)
        else:
            print(f"{Colors.WARNING}Aviso: Arquivo {file} não encontrado localmente.{Colors.ENDC}")
    print(f"{Colors.OKGREEN}Cópia concluída.{Colors.ENDC}\n")

def clear_logs():
    print(f"{Colors.HEADER}--- 2. Limpando Logcat (Buffer) ---{Colors.ENDC}")
    run_command(f'"{ADB_PATH}" logcat -c')
    print(f"{Colors.OKGREEN}Logs antigos limpos.{Colors.ENDC}\n")

def clear_screen():
    # Limpa a tela do terminal (cls no Windows)
    os.system('cls' if os.name == 'nt' else 'clear')

def stream_logs():
    print(f"{Colors.HEADER}--- 3. Monitorando Logs ('{FILTER_KEYWORD}') ---{Colors.ENDC}")
    print(f"{Colors.WARNING}Pressione Ctrl+C para parar.{Colors.ENDC}\n")
    
    # Inicia o processo do logcat
    process = subprocess.Popen(
        [ADB_PATH, "logcat", "-v", "time"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding='utf-8',
        errors='replace'
    )

    try:
        # Lê linha por linha em tempo real
        while True:
            line = process.stdout.readline()
            if not line:
                break
            
            # FILTRO: Só imprime se tiver "Sidekick" ou erro de Lua
            if FILTER_KEYWORD in line or "luajit" in line or "runtime error" in line.lower():
                # Destaca a palavra Sidekick em Verde
                formatted_line = line.strip().replace(FILTER_KEYWORD, f"{Colors.OKGREEN}{Colors.BOLD}{FILTER_KEYWORD}{Colors.ENDC}")
                print(formatted_line)
                
    except KeyboardInterrupt:
        print(f"\n{Colors.OKBLUE}Monitoramento encerrado pelo usuário.{Colors.ENDC}")
        process.terminate()

# --- EXECUÇÃO ---
if __name__ == "__main__":
    # 1. Copiar Arquivos
    sync_files()
    
    # 2. Limpar Logcat do Android
    clear_logs()
    
    # Pequena pausa para garantir que o ADB processou
    time.sleep(1)
    
    # 3. Limpar tela do PC
    clear_screen()
    
    # 4. Rodar Logcat filtrado
    stream_logs()
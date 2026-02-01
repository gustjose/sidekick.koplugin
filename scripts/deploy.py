import subprocess
import os
import sys
import time

# --- CONFIGURAÇÕES ---
ADB_PATH = r"C:\Program Files\Android Tools\adb.exe"
REMOTE_PATH = "/storage/emulated/0/koreader/plugins/sidekick.koplugin/"

# Define a raiz do projeto baseada na localização deste script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR) # Pasta sidekick.koplugin/

FILES_TO_SYNC = [
    "src/main.lua",
    "src/progress.lua",
    "src/_meta.lua",
    "src/utils.lua"
]

# Termo para filtrar no log
FILTER_KEYWORD = "Sidekick"

class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def run_command(command):
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"{Colors.FAIL}Erro: {command}{Colors.ENDC}")
        print(result.stderr)
        return False
    return True

def sync_files():
    print(f"{Colors.HEADER}--- 1. Copiando arquivos (src -> Android) ---{Colors.ENDC}")
    
    if not os.path.exists(ADB_PATH):
        print(f"{Colors.FAIL}ERRO: ADB não encontrado em: {ADB_PATH}{Colors.ENDC}")
        sys.exit(1)

    for relative_path in FILES_TO_SYNC:
        # Caminho completo no PC
        local_file = os.path.join(PROJECT_ROOT, relative_path)
        
        if os.path.exists(local_file):
            print(f"Enviando {Colors.OKBLUE}{os.path.basename(local_file)}{Colors.ENDC}...")
            
            # NOTA: Enviamos para REMOTE_PATH direto. O ADB 'push' de um arquivo 
            # para uma pasta coloca o arquivo na raiz daquela pasta.
            # Isso "achata" a estrutura (src/main.lua vira sidekick.koplugin/main.lua)
            cmd = f'"{ADB_PATH}" push "{local_file}" "{REMOTE_PATH}"'
            run_command(cmd)
        else:
            print(f"{Colors.WARNING}Aviso: Arquivo não encontrado: {local_file}{Colors.ENDC}")
            
    print(f"{Colors.OKGREEN}Cópia concluída.{Colors.ENDC}\n")

def clear_logs():
    print(f"{Colors.HEADER}--- 2. Limpando Logcat ---{Colors.ENDC}")
    run_command(f'"{ADB_PATH}" logcat -c')

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def stream_logs():
    print(f"{Colors.HEADER}--- 3. Monitorando Logs ('{FILTER_KEYWORD}') ---{Colors.ENDC}")
    print(f"{Colors.WARNING}Pressione Ctrl+C para parar.{Colors.ENDC}\n")
    
    process = subprocess.Popen(
        [ADB_PATH, "logcat", "-v", "time"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding='utf-8',
        errors='replace'
    )

    try:
        while True:
            line = process.stdout.readline()
            if not line: break
            
            if FILTER_KEYWORD in line or "luajit" in line or "runtime error" in line.lower():
                formatted_line = line.strip().replace(FILTER_KEYWORD, f"{Colors.OKGREEN}{Colors.BOLD}{FILTER_KEYWORD}{Colors.ENDC}")
                print(formatted_line)
                
    except KeyboardInterrupt:
        print(f"\n{Colors.OKBLUE}Encerrado.{Colors.ENDC}")
        process.terminate()

if __name__ == "__main__":
    sync_files()
    clear_logs()
    time.sleep(1)
    clear_screen()
    stream_logs()
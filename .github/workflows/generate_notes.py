import os
from google import genai
from google.genai import types

def generate_notes():
    try:
        api_key = os.environ.get("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY não encontrada nas variáveis de ambiente.")

        client = genai.Client(api_key=api_key)

        # Leitura segura dos arquivos gerados pelo Git
        commits = ""
        diff = ""
        
        if os.path.exists("commits.txt"):
            with open("commits.txt", "r", encoding="utf-8") as f:
                commits = f.read()
        
        if os.path.exists("changes.diff"):
            with open("changes.diff", "r", encoding="utf-8") as f:
                # Limita o diff para não estourar tokens (aprox 15k caracteres)
                diff = f.read()[:15000]

        system_instruction = "You are a specialized tool that outputs ONLY raw Markdown for GitHub Releases. No conversational text, no greetings, no backticks wrapping the whole content."
        
        prompt = f"""Generate professional release notes in Markdown for the 'Sidekick' KOReader Plugin.
        Version: {os.environ.get("TAG_NAME", "Next Version")}
        
        Structure:
        ## Features
        ## Bug Fixes
        ## Technical Changes (Refactoring, Logic updates)

        CONTEXT:
        This plugin syncs reading progress (page, percent, xpath) between devices using Syncthing.
        
        COMMITS:
        {commits}

        DIFF SUMMARY:
        {diff}
        """

        print("Enviando para o Gemini... Aguarde.")
        
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                temperature=0.3 # Menor temperatura para ser mais factual
            ),
        )

        clean_text = response.text.strip()
        
        # Limpeza extra garantida
        if clean_text.startswith("```markdown"):
            clean_text = clean_text.replace("```markdown", "", 1)
        if clean_text.startswith("```"):
            clean_text = clean_text.replace("```", "", 1)
        if clean_text.endswith("```"):
            clean_text = clean_text[:-3]

        with open("gemini_notes.md", "w", encoding="utf-8") as f:
            f.write(clean_text.strip())

        print("✅ Sucesso! O arquivo 'gemini_notes.md' foi gerado.")

    except Exception as e:
        print(f"❌ ERRO NO SCRIPT PYTHON: {str(e)}")
        # Cria um arquivo de fallback para não quebrar a pipeline
        with open("gemini_notes.md", "w", encoding="utf-8") as f:
            f.write(f"Release automatica. (Erro na geração IA: {str(e)})")

if __name__ == "__main__":
    generate_notes()
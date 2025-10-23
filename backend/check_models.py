import google.generativeai as genai
import os
from dotenv import load_dotenv

load_dotenv() # Load your API key from the .env file

genai.configure(api_key=os.environ["GEMINI_API_KEY"])

print("--- Available Models ---")
for m in genai.list_models():
  # Check if the model supports the 'generateContent' method
  if 'generateContent' in m.supported_generation_methods:
    print(f"Model Name: {m.name}")
print("------------------------")
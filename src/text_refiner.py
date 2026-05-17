#!/usr/bin/env python3
"""
Text Refiner - Cleans up speech transcription.
Step 1: Regex removes filler words (instant)
Step 2: LLM adds punctuation only (fast, no reformulation)
"""
import re
import json
import urllib.request
import urllib.error
from typing import Optional


# Filler words to remove (Czech + English)
_FILLERS_CS = [
    r'\bhmm\b', r'\behm\b', r'\beem\b', r'\bjakože\b',
    r'\bvlastně\b', r'\bprostě\b', r'\btakhle\b',
    r'\btohleto\b', r'\bjaksi\b', r'\bže jo\b',
]

_FILLERS_EN = [
    r'\bumm?\b', r'\buhh?\b', r'\blike\b(?=\s*,?\s*(I|we|the|it|you|he|she|they))',
    r'\byou know\b', r'\bI mean\b(?=\s*,)',
]

# Compile patterns
_FILLER_PATTERN_CS = re.compile('|'.join(_FILLERS_CS), re.IGNORECASE)
_FILLER_PATTERN_EN = re.compile('|'.join(_FILLERS_EN), re.IGNORECASE)

# Czech-specific characters for language detection
_CZECH_CHARS = set("áčďéěíňóřšťúůýž")

# LLM prompt - ONLY punctuation, nothing else
_PUNCT_PROMPT_CS = 'Přidej interpunkci do českého textu. NEMĚŇ slova. Pouze přidej tečky, čárky a velká písmena na začátku vět. Vrať pouze text s interpunkcí.'
_PUNCT_PROMPT_EN = 'Add punctuation to this English text. Do NOT change any words. Only add periods, commas, and capitalize first letters of sentences. Return only the punctuated text.'


def _detect_language(text: str) -> str:
    """Simple heuristic to detect if text is Czech or English"""
    lower = text.lower()
    if any(c in _CZECH_CHARS for c in lower):
        return "cs"
    return "en"


def _remove_fillers(text: str, lang: str) -> str:
    """Remove filler words using regex (instant)"""
    pattern = _FILLER_PATTERN_CS if lang == "cs" else _FILLER_PATTERN_EN
    cleaned = pattern.sub('', text)
    # Clean up double spaces and leading/trailing whitespace
    cleaned = re.sub(r'\s+', ' ', cleaned).strip()
    return cleaned


class TextRefiner:
    """Cleans speech transcription: removes fillers + adds punctuation"""

    def __init__(
        self,
        model: str = "llama3.1:8b",
        ollama_url: str = "http://localhost:11434",
        timeout: int = 10
    ):
        self.model = model
        self.ollama_url = ollama_url
        self.timeout = timeout
        self._available = None

    def is_available(self) -> bool:
        """Check if Ollama is running and the model is available"""
        if self._available is not None:
            return self._available

        try:
            req = urllib.request.Request(
                f"{self.ollama_url}/api/tags",
                method="GET"
            )
            with urllib.request.urlopen(req, timeout=2) as resp:
                data = json.loads(resp.read())
                models = [m.get("name", "") for m in data.get("models", [])]
                self._available = any(
                    self.model.split(":")[0] in m for m in models
                )
                return self._available
        except Exception:
            self._available = False
            return False

    def refine(self, raw_text: str) -> Optional[str]:
        """
        Clean up speech transcription:
        1. Remove filler words (regex, instant)
        2. Add punctuation via LLM (fast)
        
        Falls back to regex-only if LLM unavailable.
        """
        if not raw_text or not raw_text.strip():
            return None

        # Skip very short text
        if len(raw_text.strip().split()) <= 3:
            return raw_text.strip()

        # Step 1: Detect language and remove fillers (instant)
        lang = _detect_language(raw_text)
        cleaned = _remove_fillers(raw_text, lang)

        if not cleaned:
            return None

        # Step 2: Add punctuation via LLM
        punctuated = self._add_punctuation(cleaned, lang)
        return punctuated if punctuated else cleaned

    def _add_punctuation(self, text: str, lang: str) -> Optional[str]:
        """Add punctuation using Ollama LLM"""
        system_prompt = _PUNCT_PROMPT_CS if lang == "cs" else _PUNCT_PROMPT_EN

        try:
            payload = json.dumps({
                "model": self.model,
                "system": system_prompt,
                "prompt": text,
                "stream": False,
                "options": {
                    "temperature": 0.0,
                    "num_predict": 300,  # Punctuated text is ~same token count as input
                }
            }).encode("utf-8")

            req = urllib.request.Request(
                f"{self.ollama_url}/api/generate",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST"
            )

            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                result = json.loads(resp.read())
                punctuated = result.get("response", "").strip()

                # Remove any quotes LLM might wrap it in
                if punctuated.startswith('"') and punctuated.endswith('"'):
                    punctuated = punctuated[1:-1]

                if not punctuated:
                    return None

                # Sanity: if output is way different length, LLM went off rails
                if len(punctuated) > len(text) * 1.5 or len(punctuated) < len(text) * 0.5:
                    print(f"Refiner: LLM output length mismatch, using regex-only", flush=True)
                    return None

                return punctuated

        except urllib.error.URLError:
            self._available = False
            return None
        except Exception as e:
            print(f"Refiner: {e}", flush=True)
            return None

    def reset_availability(self):
        """Reset cached availability check"""
        self._available = None

# Možnosti zrychlení transkripce

## Současný stav

**Nastavení:**
- Threads: 4
- Beam size: 5 (lepší přesnost, ale pomalejší)
- Best-of: 5 (lepší přesnost, ale pomalejší)
- Model: medium (~1.5GB)

**Typický čas:**
- 5-10 sekund nahrávky = cca 3-5 sekund transkripce

---

## Možnosti zrychlení

### 1. **Více vláken (threads)**
```python
"-t", "8"  # Místo 4, využije více CPU jader
```
✅ **Výhoda:** Rychlejší, žádná ztráta kvality
❌ **Nevýhoda:** Vyšší vytížení CPU

**Zrychlení:** 30-50% rychlejší

---

### 2. **Snížit beam size**
```python
"-bs", "3"  # Místo 5
"-bo", "3"  # Místo 5
```
✅ **Výhoda:** Výrazně rychlejší
⚠️ **Nevýhoda:** Mírně nižší přesnost (ale pořád dobrá)

**Zrychlení:** 40-60% rychlejší

---

### 3. **Menší model (tiny/base místo medium)**
```python
model = "ggml-base.bin"  # Místo ggml-medium.bin
```
✅ **Výhoda:** Velmi rychlé
❌ **Nevýhoda:** Horší přesnost pro češtinu

**Zrychlení:** 3-5x rychlejší
**Nedoporučeno pro češtinu**

---

### 4. **GPU akcelerace (Metal na Mac)**
Whisper.cpp automaticky používá Metal na Mac, pokud je k dispozici.

Zkontrolovat:
```bash
# V terminálu při spuštění vidět:
# "ggml_metal_init: loaded kernel..." = GPU je použito
```

✅ Již aktivní automaticky

---

### 5. **Streaming / Real-time (složitější)**
Whisper.cpp má `whisper-server` pro streaming transkripci.

❌ **Nevýhoda:** 
- Složitá implementace
- Vyžaduje server/client architekturu
- Pořád musí čekat na celou větu

**Není to "on-the-fly"** - Whisper model potřebuje celý audio kontext.

---

## Doporučení pro zrychlení

### **Optimální nastavení pro rychlost + kvalitu:**

```python
cmd = [
    self.whisper_bin,
    "-m", self.model_path,
    "-f", audio_file,
    "-t", "8",              # ✅ Více vláken
    "-nt",
    "-bo", "3",             # ✅ Sníženo z 5
    "-bs", "3",             # ✅ Sníženo z 5
]
```

**Očekávaný výsledek:**
- 5-10s nahrávky → **1-2s transkripce** (místo 3-5s)
- Přesnost: pořád velmi dobrá pro češtinu
- CPU: trochu více vytížený

---

## Proč není možné "on-the-fly"?

Whisper model **není streamovací**:
- Potřebuje celý audio kontext (celou větu)
- Rozhoduje podle kontextu co bylo řečeno
- Nemůže transkribovat po slovech

**Alternativa:** Použít jiný model jako Vosk nebo Kaldi (ale mnohem horší kvalita pro češtinu)

---

## Co implementovat?

### **Quick win - jen změnit parametry:**
1. Zvýšit threads na 8
2. Snížit beam size/best-of na 3

### **Změnit v kódu:**
`src/speech_to_text.py` řádky 121-124

---

## Test rychlosti

```bash
# Současné nastavení
time ./whisper.cpp/build/bin/whisper-cli -m whisper.cpp/models/ggml-medium.bin -f test.wav -t 4 -bo 5 -bs 5

# Optimalizované nastavení  
time ./whisper.cpp/build/bin/whisper-cli -m whisper.cpp/models/ggml-medium.bin -f test.wav -t 8 -bo 3 -bs 3
```

**Očekávané zrychlení:** 50-70% rychlejší

---

## Shrnutí

**Nejlepší volba:**
- ✅ Zvýšit threads na 8
- ✅ Snížit beam na 3
- ✅ Ponechat medium model (kvalita pro češtinu)

**Výsledek:** 
- Rychlejší o cca 60%
- Pořád výborná kvalita
- Žádná složitá změna

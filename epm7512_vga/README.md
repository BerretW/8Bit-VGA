# EPM7512 VGA Adapter pro Project65

Tento projekt zalozi jednoduchy VGA adapter v CPLD (EPM7512) s externi SRAM.
Navrh je urceny pro pocitac Project65 popisany v Project65.md a vychazi ze signalu karty popsaných v pcb/netlist.

## Co projekt dela

- VGA casovani 640x480 @ 60 Hz (pixel clock ~25 MHz)
- textovy rezim 80x30 znaku (8x16)
- znakovy buffer v externi SRAM (kody znaku)
- font je v externi SRAM a nahrava ho CPU (zadna font ROM v CPLD)
- foreground/background barva nastavitelna 8bit registrem (3:3:2)
- testovaci pin `test_mode`: pri log.1 se zapne interni VGA demo vzor

## Souborova struktura

- quartus/epm7512_vga.qpf - Quartus projekt
- quartus/epm7512_vga.qsf - Global assignments a clock constraint
- src/epm7512_vga_adapter.v - Top-level Verilog modul
- pins/epm7512_pin_template.qsf - sablona pin assignmentu pro EPM7512
- examples/font_eeprom_24lc64_65c02.asm - 65C02 I2C rutiny pro 24LC64 + kopie fontu EEPROM <-> SRAM

## Registr interface (MEMR/MEMW, adresa C0xx)

- C000 REG_CTRL
  - bit0: 1 = video enable, 0 = blank
- C001 REG_FG_COLOR (3:3:2)
- C002 REG_BG_COLOR (3:3:2)
- C003 REG_TXT_BASE_LO  (base znakove RAM [7:0])
- C004 REG_TXT_BASE_HI  (base znakove RAM [15:8])
- C005 REG_TXT_PTR_LO   (CPU pointer pro znakovy buffer [7:0])
- C006 REG_TXT_PTR_HI   (CPU pointer pro znakovy buffer [15:8])
- C007 REG_TXT_DATA     (cteni/zapis znaku na REG_TXT_PTR; pointer auto++)
- C008 REG_FONT_BASE_LO (base fontu v SRAM [7:0])
- C009 REG_FONT_BASE_HI (base fontu v SRAM [15:8])
- C00A REG_FONT_PTR_LO  (CPU pointer pro font data [7:0])
- C00B REG_FONT_PTR_HI  (CPU pointer pro font data [15:8])
- C00C REG_FONT_DATA    (cteni/zapis fontu na REG_FONT_PTR; pointer auto++)
- C00D REG_STATUS       (bit0 = vblank)
- C00E REG_EE_I2C_CTRL  (EEPROM I2C linky, bit0=SCL, bit1=SDA drive-low)
- C00F REG_EE_I2C_STAT  (bit0=SDA sample, bit1=SCL out, bit2=SDA drive-low)

Poznamka: dekodovani je nastavene na cpu_a[15:8] == 0xC0.

## Testovaci rezim

Pokud je vstup `test_mode` v log.1, CPLD prepne VGA vystup do interniho
demo rezimu (barevny vzor) a neni zavisle na text/fontech v SRAM.

To je vhodne pro oziveni karty po nahrani bitstreamu:

1. naprogramovat CPLD,
2. privest HI na `test_mode`,
3. overit, ze na VGA bezi demo obraz.

V demo top-levelu (`epm7512_vga_demo`) je navic test mode ovladatelny i z CPU
pres 6502 sbernici s jedinym signalem `RW`:

- adresa C000, bit0
  - zapis 1: zapne demo rezim
  - zapis 0: vypne demo rezim
  - cteni vraci aktualni stav v bitu0

Aktivni demo vystup je OR kombinace externiho pinu `test_mode` a tohoto registru.

EEPROM (24LC64-I/P) je pripojena pres I2C linky eep_scl/eep_sda.
Implementace je zamerne bit-bang: CPU primo ovlada SCL/SDA pres registry,
takze muze fonty z EEPROM nacitat do SRAM (REG_FONT_DATA) i nahravat nove.

I2C registry detaily:

- REG_EE_I2C_CTRL (write/read)
  - bit0: SCL vystup (1=H, 0=L)
  - bit1: SDA drive-low (1=tahne SDA na 0, 0=pusti SDA do Z)
- REG_EE_I2C_STAT (read)
  - bit0: aktualni stav SDA na pinu
  - bit1: aktualni stav vystupu SCL
  - bit2: aktualni SDA drive-low stav

Prakticka poznamka k HW:

- I2C potrebuje pull-up odpory na SCL i SDA (typicky 4k7-10k na 5V nebo 3V3 dle zapojeni).
- Pro 24LC64 je standardni 7bit adresa 0x50 (A2..A0 podle zapojeni pinu).

## 65C02 software podpora (example)

V souboru examples/font_eeprom_24lc64_65c02.asm jsou hotove rutiny:

- vga_font_ptr_set (nastavi REG_FONT_PTR_LO/HI)
- eep_font_to_vga (blokovy prenos z EEPROM do REG_FONT_DATA streamu)
- vga_font_to_eep (blokovy prenos z REG_FONT_DATA streamu do EEPROM)

Rutiny pouzivaji 24LC64 pres bit-bang I2C na C00E/C00F.
Pouzita je bezpecna byte-write varianta s ACK pollingem.

Typicky postup pro nahrani celeho fontu 256x16 (4096 B) z EEPROM:

1. Nastavit REG_FONT_PTR na zacatek font bufferu v SRAM (napr. 0x1000).
2. Nastavit EEPROM start adresu (ZP_EEP_ADDR_HI:LO).
3. Nastavit delku na 0x1000 bajtu (ZP_LEN_HI:LO).
4. Zavolat eep_font_to_vga.

Format fontu v RAM:

- 256 znaku
- 16 bajtu na znak (radky 0..15)
- 1 bajt = 8 pixelu zleva doprava (bit7 vlevo)

## Rychly start

1. Otevrit quartus/epm7512_vga.qpf v Quartus II.
2. Upravit DEVICE v quartus/epm7512_vga.qsf podle skutecneho pouzdra EPM7512.
3. Dopsat pin assignment v pins/epm7512_pin_template.qsf.
4. Pridat pin file do projektu nebo obsah zkopirovat do hlavniho .qsf.
5. Prelozit projekt a naprogramovat CPLD.

## Dulezite poznamky

- Projekt je zamerne jednoduchy a pocita s jednim portem SRAM.
- Behem CPU pristupu do REG_TXT_DATA/REG_FONT_DATA ma CPU prioritu nad video ctenim.
- Aktualni verze pouziva 16bit adresaci prostor SRAM (0x0000-0xFFFF).
- Doporucena SRAM mapa:
  - text buffer:  0x0000 .. 0x095F (80x30 = 2400 B)
  - font buffer:  0x1000 .. 0x1FFF (256x16 = 4096 B)
- Pokud je na karte osazen jiny oscilator nez 25 MHz/25.175 MHz,
  upravte create_clock v quartus/epm7512_vga.qsf.
- Signaly IOR/IOW jsou na portech kvuli kompatibilite, ale aktualni
  dekoder pouziva MEMR/MEMW.

---

## Lightweight verze: `epm7512_vga_adapter_lite.v`

Zjednodušená verze zaměřená na minimalizaci zdrojů CPLD.

### Rozdíly vůči plné verzi:

- **Bez I2C** — odpadá bit-bang řízení EEPROM  
- **Bez barevného mixu** — jen bílý papír/černý tisk (FG=0xFFFFFF, BG=0x000000)
- **Bez dynamických base adres** — hardcoded:
  - Text buffer: 0x0000 (80×60 grid = 4800 B, pokud plně osadíme)
  - Font buffer: 0x1000 (256 znaků × 16 B = 4096 B)
- **Bez look-ahead video pipeline** — pohodlnější síťování na úkor malé halenotní latence (OK pro text)

### Registry lite verze (MEMR/MEMW, C0xx):

- **C000** `REG_CTRL`
  - bit0: 1 = video enable, 0 = black screen
  
- **C001** `REG_TXT_PTR_LO` — CPU pointer do text bufferu [7:0]
- **C002** `REG_TXT_PTR_HI` — CPU pointer do text bufferu [15:8]
- **C003** `REG_TXT_DATA` — čtení/zápis znaku na REG_TXT_PTR; pointer auto++
  
- **C004** `REG_FONT_PTR_LO` — CPU pointer do font bufferu [7:0]
- **C005** `REG_FONT_PTR_HI` — CPU pointer do font bufferu [15:8]
- **C006** `REG_FONT_DATA` — čtení/zápis fontu na REG_FONT_PTR; pointer auto++
  
- **C007** `REG_STATUS` — bit0 = vblank (1 při V-sync)

- **C008** `REG_HW_VERSION` (read-only) — HW verze: 0x01 = lite adapter v1.0
- **C009** `REG_HW_ID` (read-only) — HW identifikátor: 0xA3 = "VGA adapter lite"

- **C00A** `REG_FG_COLOR` — Barva textu (3:3:2 RGB, default 0xFF = bílá)
  - Bit[7:5] = R (3 bity)
  - Bit[4:2] = G (3 bity)  
  - Bit[1:0] = B (2 bity, rozšířeno na 3 bity) 
  - Příklady: 0xFF = bílá, 0xE0 = červená, 0x1C = zelená, 0x03 = modrá

- **C00B** `REG_BG_COLOR` — Barva pozadí (3:3:2 RGB, default 0x00 = černá)

### Jak něco zobrazit na obrazovce

#### 1. Inicializace (62C02 kód)

```asm
VGA_BASE = $C000
REG_CTRL = $00
REG_TXT_PTR_LO = $01
REG_TXT_PTR_HI = $02
REG_TXT_DATA = $03
REG_FONT_PTR_LO = $04
REG_FONT_PTR_HI = $05
REG_FONT_DATA = $06
REG_STATUS = $07
REG_HW_VERSION = $08
REG_HW_ID = $09
REG_FG_COLOR = $0A
REG_BG_COLOR = $0B

HW_VERSION_LITE = $01
HW_ID_LITE = $A3

; Ověření komunikace: čtení HW verze
  LDA VGA_BASE + REG_HW_VERSION
  CMP #HW_VERSION_LITE
  BNE error_no_hw      ; Zkrz, VGA adapter není připojen
  
; Ověření ID
  LDA VGA_BASE + REG_HW_ID
  CMP #HW_ID_LITE
  BNE error_wrong_hw   ; Chyba: neznámý HW
  
; Zapnout video
  LDA #$01
  STA VGA_BASE + REG_CTRL
```

#### 2. Nahraní fontu do SRAM (do 0x1000)

```asm
; Nastavit font pointer na 0x1000
  LDA #$00
  STA VGA_BASE + REG_FONT_PTR_LO
  LDA #$10
  STA VGA_BASE + REG_FONT_PTR_HI

; Nyní čteme/píšeme do REG_FONT_DATA a pointer se auto-inkrementuje
; Např. přepsat všech 256 znaků × 16 bajtů = 4096 B:
  LDY #$00         ; outer loop: znaky
loop_char:
  LDX #$10         ; inner loop: 16 bajtů na znak
loop_byte:
  LDA font_data, X ; tvoj font ROM nebo data
  STA VGA_BASE + REG_FONT_DATA
  DEX
  BNE loop_byte
  
  CPY #$FF         ; 256 znaků?
  BEQ font_done
  INY
  BRA loop_char
font_done:
```

#### 3. Zápis textu do text bufferu (0x0000)

Text buffer je rozdělený na **80 sloupců × 60 řádků** (480 znaků celkem).

Řádek `row` začíná na adrese: `row * 80`

```asm
; Napsat řetězec "AHOJ" na pozici (0, 0)
  LDA #$00
  STA VGA_BASE + REG_TXT_PTR_LO
  LDA #$00
  STA VGA_BASE + REG_TXT_PTR_HI
  
  LDA #'A'
  STA VGA_BASE + REG_TXT_DATA  ; ptr++ na 1
  LDA #'H'
  STA VGA_BASE + REG_TXT_DATA  ; ptr++ na 2
  LDA #'O'
  STA VGA_BASE + REG_TXT_DATA  ; ptr++ na 3
  LDA #'J'
  STA VGA_BASE + REG_TXT_DATA  ; ptr++ na 4
```

#### 4. Zápis textu na konkrétní řádek/sloupec

```asm
; Napsat na řádek 5, sloupec 10
  ; Adresa = 5*80 + 10 = 410 = 0x019A
  LDA #$9A
  STA VGA_BASE + REG_TXT_PTR_LO
  LDA #$01
  STA VGA_BASE + REG_TXT_PTR_HI
  
  LDA #'X'
  STA VGA_BASE + REG_TXT_DATA
```

#### 5. Vymazání obrazovky (vyplnit text buffer mezerami)

```asm
; Nastavit pointer na 0x0000
  LDA #$00
  STA VGA_BASE + REG_TXT_PTR_LO
  STA VGA_BASE + REG_TXT_PTR_HI
  
  LDX #$00
  LDY #$13         ; 19 = 4800/256 (počet cyklů × 256 bajtů)
loop_clear:
  LDA #' '         ; mezera
  STA VGA_BASE + REG_TXT_DATA
  DEX
  BNE loop_clear
  DEY
  BNE loop_clear
```

#### 6. Demo: Barevný vzor (bez textu)

```asm
; Vypnout video (blank screen)
  LDA #$00
  STA VGA_BASE + REG_CTRL
```

Pokud má `test_mode` pin (vstup) log. 1, CPLD zobrazuje interní barevný demo vzor.
To je užitečné pro testování HW bez obsahu SRAM.

#### 7. Změna barev textu a pozadí

Barvy jsou v **3:3:2 RGB** formátu (8 bitů):
- Bit[7:5] = **R** (3 bity, 0–7)
- Bit[4:2] = **G** (3 bity, 0–7)
- Bit[1:0] = **B** (2 bity, 0–3, rozšířeno na 3 bity)

Běžné barvy:
```
0xFF = bílá (R=7, G=7, B=3)
0xE0 = červená (R=7, G=0, B=0)
0x1C = zelená (R=0, G=7, B=0)
0x03 = modrá (R=0, G=0, B=3)
0x00 = černá (R=0, G=0, B=0)
0xF8 = žlutá (R=7, G=7, B=0)
0xE3 = purpurová (R=7, G=0, B=3)
0x1F = azurová (R=0, G=7, B=3)
```

Příklad: nastavit **bílý text na modrém pozadí**:

```asm
; Bílý text (FG = 0xFF)
  LDA #$FF
  STA VGA_BASE + REG_FG_COLOR

; Modré pozadí (BG = 0x03)
  LDA #$03
  STA VGA_BASE + REG_BG_COLOR
  
; Zapnout video
  LDA #$01
  STA VGA_BASE + REG_CTRL
```

Příklad: nastavit **žlutý text na černém pozadí**:

```asm
; Žlutý text (FG = 0xF8)
  LDA #$F8
  STA VGA_BASE + REG_FG_COLOR

; Černé pozadí (BG = 0x00)
  LDA #$00
  STA VGA_BASE + REG_BG_COLOR
```

Barev lze měnit kdykoliv za běhu — změna se projeví na dalším řádku.
Pokud chcete barevný text v řádku, musíte přepínat REG_FG_COLOR během zápisu znaku.

### Poznamka k výkonu

- Lite verze bez I2C ušetří několik procent logiky.
- Barvy jsou plně nastavitelné přes **C00A** (FG) a **C00B** (BG) registry (3:3:2 RGB).
- Default barvy po resetu: **bílý text na černém pozadí**.
- Video pipeline je jednodušší → menší latence CPU → čistší obraz.
- Stále lze čtení/zápis z/do SRAM během video refreshu (CPU má prioritu).

### Defaultní nastavení po resetu

- **REG_CTRL** = 0x00 (video disabled)
- **REG_FG_COLOR** = 0xFF (bílá)
- **REG_BG_COLOR** = 0x00 (černá)
- **text_ptr** = 0x0000
- **font_ptr** = 0x0000

### SRAM mapa pro lite verzi

```
0x0000 .. 0x12BF  Text buffer (80×60 = 4800 B)
0x1000 .. 0x1FFF  Font buffer (256×16 = 4096 B)
0x2000 .. 0xFFFF  Volné místo pro data/stack/program
```

**Pozor:** Pokud používáte méně textu (např. 80×30), máte prostor:
```
0x0000 .. 0x095F  Text buffer (80×30 = 2400 B)
0x0A00 .. 0x0FFF  Volné
0x1000 .. 0x1FFF  Font buffer (4096 B)
```

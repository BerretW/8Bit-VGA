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

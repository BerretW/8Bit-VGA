# EPM7512 VGA Adapter pro Project65

Tento projekt zalozi jednoduchy VGA adapter v CPLD (EPM7512) s externi SRAM.
Navrh je urceny pro pocitac Project65 popisany v Project65.md a vychazi ze signalu karty popsaných v pcb/netlist.

## Co projekt dela

- VGA casovani 640x480 @ 60 Hz (pixel clock ~25 MHz)
- textovy rezim 80x30 znaku (8x16)
- znakovy buffer v externi SRAM (kody znaku)
- font je v externi SRAM a nahrava ho CPU (zadna font ROM v CPLD)
- foreground/background barva nastavitelna 8bit registrem (3:3:2)

## Souborova struktura

- quartus/epm7512_vga.qpf - Quartus projekt
- quartus/epm7512_vga.qsf - Global assignments a clock constraint
- src/epm7512_vga_adapter.v - Top-level Verilog modul
- pins/epm7512_pin_template.qsf - sablona pin assignmentu pro EPM7512

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

Poznamka: dekodovani je nastavene na cpu_a[15:8] == 0xC0.

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

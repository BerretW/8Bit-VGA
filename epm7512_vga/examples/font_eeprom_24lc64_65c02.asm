; 65C02 helper routines for 24LC64-I/P on epm7512_vga_adapter
; Uses MMIO I2C bit-bang registers:
;   C00E REG_EE_I2C_CTRL (bit0=SCL, bit1=SDA drive-low)
;   C00F REG_EE_I2C_STAT (bit0=SDA sample)
;
; VGA font SRAM interface:
;   C00A REG_FONT_PTR_LO
;   C00B REG_FONT_PTR_HI
;   C00C REG_FONT_DATA (auto-increment pointer on read/write)
;
; Notes:
; - This file is intentionally standalone example code.
; - Adapt ZP addresses and symbol export/import to your firmware tree.
; - 24LC64 page write size is 32 bytes. This example uses safe byte writes.

        .setcpu "65C02"

REG_FONT_PTR_LO  = $C00A
REG_FONT_PTR_HI  = $C00B
REG_FONT_DATA    = $C00C
REG_EE_I2C_CTRL  = $C00E
REG_EE_I2C_STAT  = $C00F

I2C_CTRL_SCL     = %00000001
I2C_CTRL_SDA_LO  = %00000010

I2C_BUS_REL_HI   = I2C_CTRL_SCL
I2C_BUS_REL_LO   = $00
I2C_BUS_SDA_LO_H = I2C_CTRL_SCL | I2C_CTRL_SDA_LO
I2C_BUS_SDA_LO_L = I2C_CTRL_SDA_LO

I2C_STAT_SDA_IN  = %00000001

EEP_DEV_W        = $A0      ; 7-bit 0x50 + W
EEP_DEV_R        = $A1      ; 7-bit 0x50 + R

ZP_I2C_SHIFT     = $00
ZP_EEP_ADDR_LO   = $01
ZP_EEP_ADDR_HI   = $02
ZP_LEN_LO        = $03
ZP_LEN_HI        = $04

; ------------------------------------------------------------
; Public entry points
; ------------------------------------------------------------
;
; vga_font_ptr_set
;   A = low byte of SRAM font pointer
;   Y = high byte of SRAM font pointer
;
; eep_font_to_vga
;   Copies ZP_LEN_HI:ZP_LEN_LO bytes from 24LC64 (ZP_EEP_ADDR_HI:LO)
;   to VGA font SRAM stream (REG_FONT_DATA auto++).
;   Carry set on I2C error.
;
; vga_font_to_eep
;   Copies ZP_LEN_HI:ZP_LEN_LO bytes from VGA font SRAM stream
;   (REG_FONT_DATA auto++) to 24LC64 at ZP_EEP_ADDR_HI:LO.
;   Carry set on I2C error.

vga_font_ptr_set:
        sta REG_FONT_PTR_LO
        sty REG_FONT_PTR_HI
        rts

eep_font_to_vga:
        jsr i2c_start
        lda #EEP_DEV_W
        jsr i2c_write_byte
        bcs i2c_error_stop

        lda ZP_EEP_ADDR_HI
        jsr i2c_write_byte
        bcs i2c_error_stop

        lda ZP_EEP_ADDR_LO
        jsr i2c_write_byte
        bcs i2c_error_stop

        jsr i2c_start
        lda #EEP_DEV_R
        jsr i2c_write_byte
        bcs i2c_error_stop

@read_loop:
        lda ZP_LEN_LO
        ora ZP_LEN_HI
        beq @read_done

        lda ZP_LEN_LO
        cmp #$01
        bne @read_ack
        lda ZP_LEN_HI
        bne @read_ack

        jsr i2c_read_byte_nack
        bra @store

@read_ack:
        jsr i2c_read_byte_ack

@store:
        sta REG_FONT_DATA
        jsr eep_addr_inc
        jsr len_dec
        bra @read_loop

@read_done:
        jsr i2c_stop
        clc
        rts

vga_font_to_eep:
@write_loop:
        lda ZP_LEN_LO
        ora ZP_LEN_HI
        beq @write_done

        lda REG_FONT_DATA
        jsr eep_write_byte_at_addr
        bcs @write_err

        jsr eep_addr_inc
        jsr len_dec
        bra @write_loop

@write_done:
        clc
        rts

@write_err:
        sec
        rts

; ------------------------------------------------------------
; EEPROM single-byte write + ACK polling
; ------------------------------------------------------------

eep_write_byte_at_addr:
        sta ZP_I2C_SHIFT

        jsr i2c_start
        lda #EEP_DEV_W
        jsr i2c_write_byte
        bcs i2c_error_stop

        lda ZP_EEP_ADDR_HI
        jsr i2c_write_byte
        bcs i2c_error_stop

        lda ZP_EEP_ADDR_LO
        jsr i2c_write_byte
        bcs i2c_error_stop

        lda ZP_I2C_SHIFT
        jsr i2c_write_byte
        bcs i2c_error_stop

        jsr i2c_stop

; ACK polling after internal write cycle
@poll:
        jsr i2c_start
        lda #EEP_DEV_W
        jsr i2c_write_byte
        bcc @poll_ok
        jsr i2c_stop
        bra @poll

@poll_ok:
        jsr i2c_stop
        clc
        rts

; ------------------------------------------------------------
; I2C low-level
; ------------------------------------------------------------

i2c_start:
        lda #I2C_BUS_REL_HI
        sta REG_EE_I2C_CTRL
        jsr i2c_delay

        lda #I2C_BUS_SDA_LO_H
        sta REG_EE_I2C_CTRL
        jsr i2c_delay

        lda #I2C_BUS_SDA_LO_L
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        rts

i2c_stop:
        lda #I2C_BUS_SDA_LO_L
        sta REG_EE_I2C_CTRL
        jsr i2c_delay

        lda #I2C_BUS_SDA_LO_H
        sta REG_EE_I2C_CTRL
        jsr i2c_delay

        lda #I2C_BUS_REL_HI
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        rts

; Input: A = byte to send
; Output: C=0 ACK, C=1 NACK

i2c_write_byte:
        sta ZP_I2C_SHIFT
        ldx #$08

@wb_loop:
        asl ZP_I2C_SHIFT
        bcs @send1

@send0:
        lda #I2C_BUS_SDA_LO_L
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        lda #I2C_BUS_SDA_LO_H
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        lda #I2C_BUS_SDA_LO_L
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        bra @wb_next

@send1:
        lda #I2C_BUS_REL_LO
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        lda #I2C_BUS_REL_HI
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        lda #I2C_BUS_REL_LO
        sta REG_EE_I2C_CTRL
        jsr i2c_delay

@wb_next:
        dex
        bne @wb_loop

; ACK bit
        lda #I2C_BUS_REL_LO
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        lda #I2C_BUS_REL_HI
        sta REG_EE_I2C_CTRL
        jsr i2c_delay

        lda REG_EE_I2C_STAT
        and #I2C_STAT_SDA_IN
        bne @nack

        lda #I2C_BUS_REL_LO
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        clc
        rts

@nack:
        lda #I2C_BUS_REL_LO
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        sec
        rts

; Output: A = byte read

i2c_read_byte_ack:
        jsr i2c_read_byte_core
; send ACK (0)
        lda #I2C_BUS_SDA_LO_L
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        lda #I2C_BUS_SDA_LO_H
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        lda #I2C_BUS_SDA_LO_L
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        rts

i2c_read_byte_nack:
        jsr i2c_read_byte_core
; send NACK (1)
        lda #I2C_BUS_REL_LO
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        lda #I2C_BUS_REL_HI
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        lda #I2C_BUS_REL_LO
        sta REG_EE_I2C_CTRL
        jsr i2c_delay
        rts

i2c_read_byte_core:
        lda #$00
        ldx #$08

@rb_loop:
        pha
        lda #I2C_BUS_REL_LO
        sta REG_EE_I2C_CTRL
        jsr i2c_delay

        lda #I2C_BUS_REL_HI
        sta REG_EE_I2C_CTRL
        jsr i2c_delay

        lda REG_EE_I2C_STAT
        and #I2C_STAT_SDA_IN
        beq @bit0

        pla
        sec
        rol a
        bra @bit_done

@bit0:
        pla
        clc
        rol a

@bit_done:
        pha
        lda #I2C_BUS_REL_LO
        sta REG_EE_I2C_CTRL
        jsr i2c_delay

        dex
        bne @rb_loop

        pla
        rts

i2c_delay:
; Keep this short for 100 kHz-ish operation on typical 65C02 clocks.
        nop
        nop
        nop
        rts

; ------------------------------------------------------------
; Small helpers
; ------------------------------------------------------------

len_dec:
        lda ZP_LEN_LO
        bne @ld1
        dec ZP_LEN_HI
@ld1:
        dec ZP_LEN_LO
        rts

eep_addr_inc:
        inc ZP_EEP_ADDR_LO
        bne @ea_done
        inc ZP_EEP_ADDR_HI
@ea_done:
        rts

i2c_error_stop:
        jsr i2c_stop
        sec
        rts

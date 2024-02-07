.INCDIR         "./src/"
.INCLUDE        "include/mem.wla"


;===============================================================================
; SEGA ROM Header
;===============================================================================
; compute the checksum too
.SMSHEADER
        PRODUCTCODE     26, 7, 2
        VERSION         0
        REGIONCODE      4               ; SMS Export EU.
        RESERVEDSPACE   0xFF, 0xFF
        ROMSIZE         0xC             ; 32KB
.ENDSMS


.BANK 0 SLOT 0
;===============================================================================
; Z-80 starts here
;===============================================================================
.ORG $0000
        di                              ; Disable interrupts.
        im      1                       ; Interrupt mode 1.
        jp      f_init                  ; Jump to main program.


;===============================================================================
; VBLANK/HBLANK interrupt handler
;===============================================================================
.ORG $0038
        di                              ; Disable interrupt.
        call    f_vdp_iHandler          ; Process interrupt.
        ei                              ; Enable interrupt.
        ret


;===============================================================================
; NMI (Pause Button) interrupt handler
;===============================================================================
.ORG $0066
        retn


;===============================================================================
; INIT
;===============================================================================
.ORG $0100
f_init:
        ld      sp, $DFF0               ; Init stack pointer.

        ; ====== Clear RAM.
        xor     a
        ld      (SMS_RAM_ADDRESS), a    ; Load the value 0 to the RAM at $C000
        ld      hl, SMS_RAM_ADDRESS     ; Starting cleaning at $C000
        ld      de, SMS_RAM_ADDRESS + 1 ; Destination: next address in RAM.
        ld      bc, $1FFF               ; Copy 8191 bytes. $C000 to $DFFF.
        ldir

        ; ====== Clear VRAM.
        xor     a                       ; VRAM write address to 0.
        out     (SMS_PORTS_VDP_COMMAND), a
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      bc, $4000               ; Output 16KB of zeroes.
@loop_clear_vram:
                xor     a               ; Value to write.
                out     (SMS_PORTS_VDP_DATA), a ; Auto-incremented after each write.
                dec     bc
                ld      a, b
                or      c
                jr      nz, @loop_clear_vram

        ; ====== Load Black and White palette.
        ld      hl, plt_bw
        ld      b, plt_bw_size
        ld      c, 0
        call    f_load_palette

        ; ====== Load tile '0'
        ld      hl, tile_0
        ld      bc, tile_0_size
        ld      de, $0020
        call    f_load_asset

        ; ====== Load tile '1'
        ld      hl, tile_1
        ld      bc, tile_1_size
        ld      de, $0040
        call    f_load_asset

        ; ====== Init VDP Registers (with screen disabled).
        call    f_VDPInitialisation

        call    f_enable_screen         ; enable screen.
        ei                              ; enable interrupt.
        jr      f_main_loop

;===============================================================================
; MAIN FUNCTION
;===============================================================================
f_main_loop:
        halt                            ; wait next interrupt.
        call    DetectTVType            ; detect TV Type and draw tile.
        ei                              ; re-enable interrupt.
        jr      f_main_loop


;===============================================================================
; Function that detect PAL / NTSC TV Screen.
; From: https://www.smspower.org/Development/TVTypeDetection
;===============================================================================
DetectTVType:
        di                              ; disable interrupts

        ; ====== Setup VDP
        ld      a, %11100000            ; enable screen and VBlank interrupt.
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, SMS_VDP_REGISTER_1
        out     (SMS_PORTS_VDP_COMMAND), a

        ; ====== Init counter.
        ld      hl, $0000

        ; ====== Get VDP status.
-:      in      a, (SMS_PORTS_VDP_COMMAND)
        or      a
        jp      p, -                    ; loop until frame interrupt flag is set.

        ; do the same again, in case we were unlucky and came in just
        ; before the start of the VBlank with the flag already set.
-:      in      a, (SMS_PORTS_VDP_COMMAND)
        or      a
        jp      p, -

        ; ====== Start counting (beginning of a VBlank).
-:      inc     hl                      ; (6 cycles) increment counter until interrypt flag comes on again.
        in      a, (SMS_PORTS_VDP_COMMAND) ; (11 cycles)
        or      a                       ; (4 cycles)
        jp      p, -                    ; (10 cycles)

        ; ====== Compute the result.
        xor     a                       ; reset carry flag, also set a to 0
        ld      de, 2048                ; see if hl is more or less than 2048
        sbc     hl, de

        ;       hl >= 2048 = PAL
        ;       hl < 2048 = NTSC
        jr      c, @draw_0_for_ntsc
        jr      @draw_1_for_pal

@draw_0_for_ntsc:
        ld      hl, $3800
        ld      bc, $0100
        call    f_draw_tile
        jr      @end_draw

@draw_1_for_pal:
        ld      hl, $3800
        ld      bc, $0200
        call    f_draw_tile

@end_draw:
        ret


;===============================================================================
; Function to draw a tile in VRAM.
; in    hl:     VRAM Addr
; in    b:      Tile ID
; in    c:      Tile properties
;===============================================================================
f_draw_tile:
        ld      a, l
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, h
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, b
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, c
        out     (SMS_PORTS_VDP_DATA), a
        ret


;===============================================================================
; Function to load palette in CRAM.
; in    hl:     palette asset Addr
; in    b:      palette size
; in    c:      Bank selection
;===============================================================================
f_load_palette:
        xor     a
        or      c
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, SMS_VDP_WRITE_CRAM
        out     (SMS_PORTS_VDP_COMMAND), a
@loop_loading_colors:
                ld      a, (hl)
                out     (SMS_PORTS_VDP_DATA), a
                inc     hl
                dec     b
                jp      nz, @loop_loading_colors
        ret


;===============================================================================
; Function to load tileset in VRAM.
; in    hl:     asset addr
; in    bc:     asset size
; in    de:     VRAM Addr
;===============================================================================
f_load_asset:
        ld      a, e
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, d
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
@loop_loading_asset:
                ld      a, (hl)
                out     (SMS_PORTS_VDP_DATA), a
                inc     hl
                dec     bc
                ld      a, b
                or      c
                jr      nz, @loop_loading_asset
        ret


;===============================================================================
; Function to tell the VDP to enable screen.
;===============================================================================
f_enable_screen:
        ; Change VDP register.
        ld      a, %11100000
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, SMS_VDP_REGISTER_1
        out     (SMS_PORTS_VDP_COMMAND), a

        ei      ; Enable interrupt.

        ret


;===============================================================================
; Function triggered when VDP sent interrupt signal.
;===============================================================================
f_vdp_iHandler:
        ; Saves registers on the stack.
        push    af
        push    bc
        push    de
        push    hl

        ; Read interrupt variables.
        in      a, (SMS_PORTS_VDP_STATUS) ; Retrieve from the VDP what interrupted us.
        and     %10000000               ; VDP Interrupt information.
                ;x.......               ; 1: VBLANK Interrupt, 0: H-Line Interrupt [if enabled].
                ;.X......               ; 9 sprites on a raster line.
                ;..x.....               ; Sprite Collision.
        jr      nz, @vblank_handler

@hblank_handler:
        nop
        jp      @f_vdp_iHandler_end

@vblank_handler:
        nop

@f_vdp_iHandler_end:
        ; Set back registers from the stack.
        pop     hl
        pop     de
        pop     bc
        pop     af

        ret


;===============================================================================
; VDP Initialisation function.
;
; Use to set all VDP registers to default values.
; For register => page 16 to 19 from official guide.
;===============================================================================
f_VDPInitialisation:
        ld      hl, @vdp_default_registers
        ld      b, (@vdp_default_registers_end - @vdp_default_registers)
@loop_init_vdp:
        ld      a, (hl)
        out     (SMS_PORTS_VDP_COMMAND), a
        inc     hl
        dec     b
        jp      nz, @loop_init_vdp
        ret

@vdp_default_registers:
        .byte   %00000100               ; VDP Reg#0
                ;X|||||||               ; Disable vertical scrolling for columns 24-31.
                ; X||||||               ; Disable horizontal scrolling for rows 0-1.
                ;  X|||||               ; Mask column 0 with overscan color from register #7.
                ;   X||||               ; (IE1) HBlank Interrupt enable.
                ;    X|||               ; (EC) Shift sprites left by 8 pixels.
                ;     X||               ; (M4)  1= Use Mode 4, 0= Use TMS9918 modes (selected with M1, M2, M3).
                ;      X|               ; (M2) Must be 1 for M1/M3 to change screen height in Mode 4.
                ;       X               ; 1= No sync, display is monochrome, 0= Normal display.
        .byte   SMS_VDP_REGISTER_0
        .byte   %10100000               ; VDP Reg#1
                ;X|||||||               ; Always to 1 (no effect).
                ; X||||||               ; (BLK) 1= Display visible, 0= display blanked.
                ;  X|||||               ; (IE) VBlank Interrupt enable.
                ;   X||||               ; (M1) Selects 224-line screen for Mode 4 if M2=1, else has no effect.
                ;    X|||               ; (M3) Selects 240-line screen for Mode 4 if M2=1, else has no effect.
                ;     X||               ; No effect.
                ;      X|               ; Sprites are 1=16x16,0=8x8 (TMS9918), Sprites are 1=8x16,0=8x8 (Mode 4).
                ;       X               ; Sprite pixels are doubled in size.
        .byte   SMS_VDP_REGISTER_1
        .byte   %11111111               ; VDP Reg#2 Screen Map Base Address $3800.
        .byte   SMS_VDP_REGISTER_2
        .byte   %11111111               ; VDP Reg#3 Always set to $FF.
        .byte   SMS_VDP_REGISTER_3
        .byte   %11111111               ; VDP Reg#4 Always set to $FF.
        .byte   SMS_VDP_REGISTER_4
        .byte   %11111111               ; VDP Reg#5 Base Address for Sprite Attribute Table.
        .byte   SMS_VDP_REGISTER_5
        .byte   %11111111               ; VDP Reg#6 Base Address for Sprite Pattern.
        .byte   SMS_VDP_REGISTER_6
        .byte   %00000000               ; VDP Reg#7 Border Color from second bank.
        .byte   SMS_VDP_REGISTER_7
        .byte   %00000000               ; VDP Reg#8 Horizontal Scroll Value.
        .byte   SMS_VDP_REGISTER_8
        .byte   %00000000               ; VDP Reg#9 Vertical Scroll Value.
        .byte   SMS_VDP_REGISTER_9
        .byte   %11111111               ; VDP Reg#10 Raster Line Interrupt.
        .byte   SMS_VDP_REGISTER_10
@vdp_default_registers_end:


.BANK 1 SLOT 1
.ORG $0000
;===============================================================================
; ASSETS DATA
;===============================================================================
plt_bw:
.INCBIN "assets/palettes/bw.plt.bin" fsize plt_bw_size

tile_0:
.INCBIN "assets/tiles/0.tile.bin" fsize tile_0_size

tile_1:
.INCBIN "assets/tiles/1.tile.bin" fsize tile_1_size
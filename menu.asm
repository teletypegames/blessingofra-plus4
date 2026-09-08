; -----------------------------------------------------------
; menu.asm - full-screen menu card: big BLESSING / OF RA
; title under the rolling gold sun wash, and a four-item
; menu: play / options / story / credits (joystick or w/s
; up/down + fire, space or return)
; -----------------------------------------------------------

MENU_ITEMS = 4

menu_init:
    jsr clear_screen

    ; a dark maze weaves behind the whole card
    lda #MAZE_CW
    sta mzcw
    lda #MAZE_CH
    sta mzch
    jsr set_maze
    lda #BROWN
    sta latwcol
    sta latpcol
    jsr draw_lattice
    jsr gen_init
    jsr gen_maze_full

    ; a clean panel for the menu itself (rows 13-24, cols 4-35)
    ldx #13
mi_panel:
    stx ptmp
    jsr row_ptr
    ldy #35
mi_pcol:
    lda #$20
    sta (scrlo),y
    lda #BLACK
    sta (collo),y
    dey
    cpy #3
    bne mi_pcol
    ldx ptmp
    inx
    cpx #25
    bne mi_panel

    +prbig 1, 4, YELLOW, txt_t1, 8
    +prbig 7, 10, ORANGE, txt_t2, 5
    +prtext 13, 13, LGREY, txt_ttgname, 14

    lda #0
    sta menusel
    sta washphase

    +setupd menu_update
    rts

menu_update:
    jsr wash_title       ; gold sun wash on both title lines

    ; joystick up/down steps the cursor (edge detected)
    jsr read_joy
    lda joyb
    and #3
    beq mu_udrel
    lda udheld
    bne mu_udend
    lda #1
    sta udheld
    lda joyb
    and #1               ; up
    beq mu_down
    lda menusel
    beq mu_udend
    dec menusel
    lda #SFX_CURSOR
    jsr sfx_play
    jmp mu_udend
mu_down:
    lda menusel
    cmp #MENU_ITEMS-1
    beq mu_udend
    inc menusel
    lda #SFX_CURSOR
    jsr sfx_play
    jmp mu_udend
mu_udrel:
    lda #0
    sta udheld
mu_udend:

    ; footer: both control lines always visible
    +prtext 23, 7, LGREY, txt_info, txt_infoe-txt_info
    +prtext 24, 11, LGREY, txt_info2, txt_info2e-txt_info2

    ; the menu items: the picked line is yellow
    ldx #0
mm_items:
    txa
    pha
    jsr draw_mitem
    pla
    tax
    inx
    cpx #MENU_ITEMS
    bne mm_items

    ; blinking '>' cursor in front of the picked line
    lda #$20
    sta SCREEN+15*40+15
    sta SCREEN+17*40+15
    sta SCREEN+19*40+15
    sta SCREEN+21*40+15
    lda framectr
    and #16
    bne mu_start
    ldx menusel
    lda mcur_lo,x
    sta scrlo
    lda mcur_hi,x
    sta scrhi
    ldy #0
    lda #62              ; '>'
    sta (scrlo),y
    lda scrhi
    clc
    adc #COLOFF          ; same cell in color RAM
    sta scrhi
    lda #YELLOW
    sta (scrlo),y

mu_start:
    ; fire or space opens the picked line
    jsr start_edge
    beq mu_done
    lda #SFX_SELECT
    jsr sfx_play
    lda menusel
    beq mg_play
    cmp #1
    beq mg_options
    cmp #2
    beq mg_story
    +fadeto credits_init ; every screen change fades to black
mg_play:
    lda opt_level        ; a fresh run: the picked start level,
    clc                  ; clock zeroed
    adc #MZMIN-1
    sta mzsize
    lda #0
    sta tframe
    sta tsec
    sta tmin
    +fadeto play_init
mg_options:
    +fadeto options_init
mg_story:
    +fadeto story_init
mu_done:
    rts

; ---- draw menu item X, yellow when it is the picked one ----
draw_mitem:
    lda mitem_lo,x
    sta txtlo
    lda mitem_hi,x
    sta txthi
    lda mitem_row,x
    sta prow
    lda #17
    sta pcol
    lda mitem_len,x
    sta plen
    lda #WHITE
    cpx menusel
    bne dm_store
    lda #YELLOW
dm_store:
    sta pcolor
    jmp print_text

; ---- menu tables ----
mitem_lo:
    !byte <txt_play, <txt_options, <txt_story, <txt_credits
mitem_hi:
    !byte >txt_play, >txt_options, >txt_story, >txt_credits
mitem_len: !byte 4, 7, 5, 7
mitem_row: !byte 15, 17, 19, 21
mcur_lo:                 ; cursor cells: column 15 of those rows
    !byte <(SCREEN+15*40+15), <(SCREEN+17*40+15)
    !byte <(SCREEN+19*40+15), <(SCREEN+21*40+15)
mcur_hi:
    !byte >(SCREEN+15*40+15), >(SCREEN+17*40+15)
    !byte >(SCREEN+19*40+15), >(SCREEN+21*40+15)

; ---- menu texts ----
txt_play:    !scr "play"
txt_options: !scr "options"
txt_credits: !scr "credits"
txt_info:    !scr "p1: joy2/wasd - the worker"
txt_infoe:
txt_info2:   !scr "p2: joy1/ijkl - ra"
txt_info2e:

; ---- menu variables ----
menusel:   !byte 0       ; picked line: 0-3
udheld:    !byte 0       ; joystick up/down edge detection state

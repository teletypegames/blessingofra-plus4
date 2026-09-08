; -----------------------------------------------------------
; pyramid.asm - the title card between the TTG logo and the
; menu: big BLESSING / OF RA under the rolling gold wash, a
; sandstone pyramid rising below with the trapped worker
; glinting at its peak and the sun of ra pulsing beside it;
; advances to the menu after a few seconds or on fire
; -----------------------------------------------------------

PYR_TIME = 250           ; frames before it advances on its own

pyramid_init:
    jsr clear_screen

    +prbig 1, 4, YELLOW, txt_t1, 8
    +prbig 7, 10, ORANGE, txt_t2, 5

    ; the pyramid: ten block rows, apex on row 13
    lda #0
    sta ptmp
py_prow:
    lda #13
    clc
    adc ptmp
    tax
    jsr row_ptr
    lda #19              ; row r spans columns 19-r .. 20+r
    sec
    sbc ptmp
    tay
    lda ptmp
    asl
    clc
    adc #2               ; 2r+2 blocks on this row
    sta rtmp2
py_pcol:
    lda #$a0
    sta (scrlo),y
    ldx ptmp
    lda pyrcols,x        ; sunlit top, shaded base
    sta (collo),y
    iny
    dec rtmp2
    bne py_pcol
    inc ptmp
    lda ptmp
    cmp #10
    bne py_prow

    ; the worker glints at the peak
    lda #$51             ; filled dot
    sta SCREEN+12*40+19
    lda #WHITE
    sta COLRAM+12*40+19

    ; the sun of ra beside the pyramid
    lda #$a0
    sta SCREEN+14*40+32
    sta SCREEN+14*40+33
    sta SCREEN+15*40+31
    sta SCREEN+15*40+32
    sta SCREEN+15*40+33
    sta SCREEN+15*40+34
    sta SCREEN+16*40+32
    sta SCREEN+16*40+33

    +prtext 24, 5, LGREY, txt_pray, txt_praye-txt_pray

    lda #PYR_TIME
    sta pyrt
    lda #0
    sta washphase
    +setupd pyramid_update
    rts

pyramid_update:
    jsr wash_title       ; the gold wash rolls down the title

    ; the sun pulses
    lda framectr
    lsr
    lsr
    lsr
    and #3
    tax
    lda sunpulse,x
    sta COLRAM+14*40+32
    sta COLRAM+14*40+33
    sta COLRAM+15*40+31
    sta COLRAM+15*40+32
    sta COLRAM+15*40+33
    sta COLRAM+15*40+34
    sta COLRAM+16*40+32
    sta COLRAM+16*40+33

    ; fire skips, otherwise wait out the timer
    jsr start_edge
    beq py_tick
    +fadeto menu_init
py_tick:
    dec pyrt
    bne py_done
    +fadeto menu_init
py_done:
    rts

; ---- tables and texts ----
pyrcols:                 ; pyramid rows top to bottom
    !byte YELLOW, YELLOW, ORANGE, ORANGE, ORANGE
    !byte ORANGE, ORANGE, BROWN, BROWN, BROWN
sunpulse:                ; the sun of ra breathes
    !byte YELLOW, YELLOW, WHITE, YELLOW
txt_pray:  !scr "a worker prays at the peak..."
txt_praye:

; ---- pyramid variables ----
pyrt:      !byte 0       ; frames left before auto-advancing

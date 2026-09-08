; -----------------------------------------------------------
; sound.asm - single-voice SFX driver on TED voice 2 (the one
; that can do noise): each effect is a waveform + start pitch
; + per-frame pitch slide + duration; the TED has no envelope,
; so the volume decays in software, a step every few frames
; -----------------------------------------------------------

sfx_init:
    lda #0
    sta TED_SND          ; silence
    sta sfx_timer
    rts

; ---- start effect A ----
sfx_play:
    tax
    lda sfxn_lo,x        ; 10-bit TED pitch: 1024 - 111840 / hz
    sta sfx_nlo
    lda sfxn_hi,x
    sta sfx_nhi
    lda sfxslide,x
    sta sfx_slide
    lda sfxdur,x
    sta sfx_timer
    lda sfxdec,x
    sta sfx_dec
    sta sfx_dcnt
    lda sfxwave,x
    sta sfx_wave
    lda #8               ; full volume, then the decay shapes it
    sta sfx_vol
    jmp sfx_out

; ---- called once per frame by the main loop ----
sfx_update:
    lda sfx_timer
    beq su_idle
    dec sfx_timer
    bne su_slide
    lda #0               ; time is up: hard-silence the voice
    sta TED_SND
    rts
su_slide:
    lda sfx_nlo          ; bend the pitch by the signed slide
    clc
    adc sfx_slide
    sta sfx_nlo
    lda sfx_slide
    bmi su_neg
    lda sfx_nhi
    adc #0
    sta sfx_nhi
    jmp su_decay
su_neg:
    lda sfx_nhi
    adc #$ff
    sta sfx_nhi
su_decay:
    dec sfx_dcnt         ; one volume step every sfx_dec frames
    bne sfx_out
    lda sfx_dec
    sta sfx_dcnt
    lda sfx_vol
    cmp #2
    bcc sfx_out
    dec sfx_vol
sfx_out:
    lda sfx_nlo
    sta TED_S2FL
    lda sfx_nhi
    and #3
    sta TED_S2FH
    lda sfx_wave
    ora sfx_vol
    sta TED_SND
su_idle:
    rts

; ---- effect tables:
; cursor, select, rotate, deny, win, lose, shot, hit ----
sfxn_lo:  !byte $a5, $1c, $69, $28, $1c, $7e, $b4, $8e
sfxn_hi:  !byte $03, $03, $02, $00, $03, $03, $03, $03
sfxslide: !byte $00, $0c, $fa, $00, $04, $f0, $fa, $f2
sfxwave:  !byte $20, $20, $60, $20, $20, $20, $20, $60
sfxdec:   !byte $01, $02, $02, $02, $05, $06, $01, $02
sfxdur:   !byte $04, $0a, $08, $0c, $28, $30, $03, $08

; ---- driver variables ----
sfx_timer: !byte 0       ; frames left of the current effect
sfx_nlo:   !byte 0       ; pitch register shadow (10 bits)
sfx_nhi:   !byte 0
sfx_slide: !byte 0       ; signed per-frame pitch step
sfx_wave:  !byte 0       ; TED_SND voice bits: $20 square, $60 noise
sfx_vol:   !byte 0       ; current volume 1-8
sfx_dec:   !byte 0       ; frames per volume step
sfx_dcnt:  !byte 0       ; frames left until the next step

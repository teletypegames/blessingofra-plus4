; -----------------------------------------------------------
; over.asm - game over screen: big red GAME OVER, fire
; retries the same level with a fresh maze, the m key backs
; out to the menu
; -----------------------------------------------------------

lose_init:
    jsr clear_screen

    lda #RED             ; the border mourns with the letters
    sta borbase

    +prbig 3, 2, RED, txt_gameover, 9

    +prtext 11, 8, WHITE, txt_caught, txt_caughte-txt_caught

    lda mzsize           ; which level claimed him
    sec
    sbc #MZMIN-1
    ora #$30
    sta txt_felld
    +prtext 13, 10, LGREY, txt_fell, txt_felle-txt_fell

    +prtext 21, 13, LGREY, txt_mmenu, txt_mmenue-txt_mmenu

    +setupd lose_update
    rts

lose_update:
    ; blink the retry prompt
    lda framectr
    and #32
    bne lu_hide
    +prtext 19, 12, YELLOW, txt_retry, txt_retrye-txt_retry
    jmp lu_input
lu_hide:
    +prtext 19, 12, YELLOW, txt_blank, txt_retrye-txt_retry
lu_input:
    ; fire or space: straight back in with a fresh maze
    jsr start_edge
    beq lu_nofire
    +fadeto play_init
lu_nofire:
    lda #$ef             ; the m key: keyboard column 4, row bit 4
    jsr key_col
    and #$10
    bne lu_done
    +fadeto menu_init
lu_done:
    rts

; ---- game over texts ----
txt_gameover: !scr "game over"
txt_caught:   !scr "the pyramid claimed you"
txt_caughte:
txt_fell:     !scr "you fell on level "
txt_felld:    !scr "1"
txt_felle:
txt_retry:    !scr "fire = try again"
txt_retrye:
txt_mmenu:    !scr "m = main menu"
txt_mmenue:

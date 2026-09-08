; -----------------------------------------------------------
; main.asm - BLESSING OF RA for the Commodore Plus/4
;   two-player pyramid escape: player 1 is a worker sealed in
;   the great pyramid, running the corridors toward the exit
;   portal while dodging the scarabs and scorpions (whose
;   venom stings fly down the corridors); player 2 is ra: the
;   cursor rides the wall corners and fire spins the four
;   wall pieces around it by 90 degrees, reshaping the maze
;   under the worker's feet; eight levels, each maze one cell
;   bigger than the last (4x4 up to 11x11)
;
; the Plus/4 port of the C64 game: same rules, same screens;
; the TED has no sprites, so the actors are software sprites
; composed into dynamic chars, the SID effects moved to the
; TED's second voice, and the status band behind the top row
; is painted by a raster interrupt
;
; Files:
;   defs.asm    - constants, zero page, macros
;   intro.asm   - TTG boot logo
;   pyramid.asm - title card: the pyramid and the sun of ra
;   menu.asm    - main menu over a dark maze backdrop
;   options.asm - optional extras: worker gun, spin cooldown,
;                 relic order
;   story.asm   - the legend + who steers what
;   credits.asm - the crew
;   play.asm    - maze generation + the game itself
;   win.asm     - escape screen, returns to the menu
;   over.asm    - game over screen with retry
;   common.asm  - shared routines, input, RNG, texts
;   sound.asm   - single-voice SFX driver on TED voice 2
;   gfx.asm     - RAM charset, software sprites, fades
;
; Build: acme -f cbm -o blessingofra_plus4.prg main.asm
; -----------------------------------------------------------

* = $1001

; ---- BASIC stub: 10 SYS 4109 ----
; so after LOAD"*",8,1 it's enough to type RUN
!byte $0b, $10           ; address of next line
!byte $0a, $00           ; line number: 10
!byte $9e                ; SYS token
!text "4109"             ; = $100d
!byte $00                ; end of line
!byte $00, $00           ; end of program

!src "defs.asm"

start:                   ; = $100d
    sei                  ; the KERNAL IRQ never runs again
    lda #BLACK
    sta BORDER
    sta BG
    lda #0
    sta spren            ; the actors arrive with the game screen
    sta framectr
    sta fheld
    jsr gfx_init         ; RAM charset (copied from ROM) + TED
    jsr sfx_init
    jsr irq_init         ; RAM in, our raster IRQ paints the band

!ifdef AUTOPLAY {        ; test builds boot straight into one state
    jsr play_init
} else {
!ifdef AUTOSTORY {
    jsr story_init
} else {
!ifdef AUTOPYRAMID {
    jsr pyramid_init
} else {
!ifdef AUTOOPTIONS {
    jsr options_init
} else {
!ifdef AUTOCREDITS {
    jsr credits_init
} else {
!ifdef AUTOWIN {
    jsr win_init
} else {
!ifdef AUTOLOSE {
    jsr lose_init
} else {
    jsr intro_init       ; TTG logo, then the pyramid, then the menu
}
}
}
}
}
}
}

; ============================================================
; main loop - one state update per PAL frame, synced to the
; raster beam as it enters the bottom border: the update (and
; the actors' redraw) runs while the beam is off the text
; rows; the loop also paints the border (event flashes decay
; back to the screen's base color)
; ============================================================
main:
    jsr wait_frame       ; raster line RAS_SYNC, once a frame
    lda bflash           ; border: flash, else the base color
    beq mb_base
    dec bflash
    lda bcolor
    jmp mb_border
mb_base:
    lda borbase
mb_border:
    sta BORDER
    inc framectr
    jsr rand8            ; stir the RNG once per frame
    jsr sfx_update       ; advance the sound effect
!ifdef RASTERDBG {       ; test builds show the update time on the border
    lda #WHITE
    sta BORDER
}
    jsr call_update
!ifdef RASTERDBG {
    lda borbase
    sta BORDER
}
    jmp main

call_update:
    jmp (updvec)         ; each update runs exactly one frame, ends with rts

; ---- wait for raster line RAS_SYNC (leave it first, so a
; fast update cannot run twice in the same frame) ----
wait_frame:
    lda RASTER
    cmp #RAS_SYNC
    beq wait_frame
wf_hit:
    lda RASTER
    cmp #RAS_SYNC
    bne wf_hit
    rts

; ============================================================
; the status band - a raster interrupt at BAND_LINE (top
; border) switches the background to statbg, a second one at
; BAND_ARM waits for BAND_END and switches it back to black
; behind row 1's solid wall tops; statbg = $ff means no band
; ============================================================
irq_init:
    sta RAM_IN           ; RAM under the ROMs: the IRQ vector is ours
    lda #<band_irq
    sta IRQVEC
    lda #>band_irq
    sta IRQVEC+1
    lda #0
    sta bandst
    lda #BAND_LINE
    sta TED_RCMP
    lda #%00000010       ; raster IRQ only, compare bit 8 = 0
    sta TED_IMASK
    lda #$ff
    sta TED_IRQ          ; drop anything pending
    cli
    rts

band_irq:
    pha
    lda #%00000010
    sta TED_IRQ          ; acknowledge the raster interrupt
    lda bandst
    bne bi_end
    lda statbg
    bmi bi_out           ; no band on this screen
    sta BG
    lda #BAND_ARM
    sta TED_RCMP
    inc bandst
    pla
    rti
bi_end:
    lda RASTER
    cmp #BAND_END
    bcc bi_end
    lda #BLACK
    sta BG
    lda #BAND_LINE
    sta TED_RCMP
    lda #0
    sta bandst
bi_out:
    pla
    rti

bandst:   !byte 0        ; 0 = waiting for the band's top, 1 = its end

; ============================================================
; the states and everything they share
; ============================================================
!src "intro.asm"
!src "pyramid.asm"
!src "menu.asm"
!src "options.asm"
!src "story.asm"
!src "credits.asm"
!src "play.asm"
!src "win.asm"
!src "over.asm"
!src "common.asm"
!src "sound.asm"
!src "gfx.asm"

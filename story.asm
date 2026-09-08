; -----------------------------------------------------------
; story.asm - the legend of the trapped worker and ra, plus
; who steers what (the old rules and controls cards merged
; into one); a static card, fire returns to the menu
; -----------------------------------------------------------

story_init:
    jsr clear_screen

    +prbig 1, 10, WHITE, txt_story, 5

    +prtext  7,  1, WHITE,  txt_s1, txt_s1e-txt_s1
    +prtext  8,  2, WHITE,  txt_s2, txt_s2e-txt_s2
    +prtext  9,  4, WHITE,  txt_s3, txt_s3e-txt_s3
    +prtext 10,  4, YELLOW, txt_s4, txt_s4e-txt_s4
    +prtext 11,  8, YELLOW, txt_s5, txt_s5e-txt_s5

    +prtext 13,  2, LRED,   txt_s6, txt_s6e-txt_s6
    +prtext 14,  4, LRED,   txt_s7, txt_s7e-txt_s7

    +prtext 16,  6, LGREEN, txt_s8, txt_s8e-txt_s8
    +prtext 17,  5, LGREY,  txt_s9, txt_s9e-txt_s9
    +prtext 18, 10, LBLUE,  txt_s10, txt_s10e-txt_s10
    +prtext 19,  3, LGREY,  txt_s11, txt_s11e-txt_s11

    +prtext 21,  6, LGREY,  txt_s12, txt_s12e-txt_s12

    +setupd story_update
    rts

story_update:
    ; blink the return prompt
    lda framectr
    and #32
    bne st_hide
    +prtext 23, 13, YELLOW, txt_return, 13
    jmp st_input
st_hide:
    +prtext 23, 13, YELLOW, txt_blank, 13
st_input:
    jsr start_edge
    beq st_stay
    +fadeto menu_init
st_stay:
    rts

; ---- story texts ----
txt_story: !scr "story"
txt_s1:  !scr "when the great pyramid rose, a worker"
txt_s1e:
txt_s2:  !scr "was sealed in its peak. he prayed to"
txt_s2e:
txt_s3:  !scr "ra until the sun god took pity:"
txt_s3e:
txt_s4:  !scr "now ra bends the pyramid's walls"
txt_s4e:
txt_s5:  !scr "to lead the worker out."
txt_s5e:
txt_s6:  !scr "beware the scarabs and the scorpions"
txt_s6e:
txt_s7:  !scr "- a scorpion's sting flies far!"
txt_s7e:
txt_s8:  !scr "p1 - the worker: joy2 / wasd"
txt_s8e:
txt_s9:  !scr "gun: fire or space, if enabled"
txt_s9e:
txt_s10: !scr "p2 - ra: joy1 / ijkl"
txt_s10e:
txt_s11: !scr "fire spins the walls at the cursor"
txt_s11e:
txt_s12: !scr "menus: fire, space or return"
txt_s12e:

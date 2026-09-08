; -----------------------------------------------------------
; play.asm - the game: eight levels of pyramid maze, each one
; cell bigger than the last (4x4 up to 11x11, always square,
; centered on screen); a fresh maze carves itself at the
; start of every level (recursive backtracker, a few steps a
; frame), player 1 (joystick 2) is the trapped worker running
; for the exit, player 2 (joystick 1) is ra: the cursor rides
; the wall corners and fire spins the four wall pieces around
; it by 90 degrees; scarabs roam the corridors on the
; worker's life, and the scorpions also spit venom stings
; down them
;
; the walls, posts and the portal are chars (the screen stays
; the wall data structure), and every actor - worker, cursor,
; bullet, enemies, sting - is a software sprite gliding
; between the cells (gfx.asm composes it into dynamic chars
; over the maze); the actors are lifted off the screen at the
; top of every frame, so the logic below always reads the
; bare maze; actor collisions are grid coordinate checks
;
; optional extras (see options.asm):
;   opt_shoot - player 1's fire shoots a bullet in the last
;               direction faced; a hit enemy respawns on a
;               random cell after RESPAWN_TIME frames
;   opt_cool  - a spin starts a COOL_TIME recharge, shown as
;               a draining 1/8-step bar on the status row
;   opt_relic - numbered relics are scattered over the cells;
;               the worker must pick them up in order before
;               the portal will take him, one more relic each
;               level (2 on level 1 up to 9 on level 8)
;
; screen layout: status on row 0 (over the colored raster
; band), the centered lattice on rows 1-23, hints on row 24
; -----------------------------------------------------------

play_init:
    jsr clear_screen
    +prtext 0, 0, WHITE, txt_level, 5
    lda mzsize           ; level number 1-8 next to the label
    sec
    sbc #MZMIN-1
    ora #$30
    sta SCREEN+6
    lda #YELLOW
    sta COLRAM+6
    lda opt_relic        ; relic mode keeps its own counter here
    bne pi_goal
    +prtext 0, 34, LGREY, txt_goal, txt_goale-txt_goal
pi_goal:
    +prtext 24, 4, DGREY, txt_hint, txt_hinte-txt_hint

    lda mzsize           ; this level's lattice: a square
    sta mzcw
    sta mzch
    jsr set_maze
    lda mzsize           ; one more enemy each level, capped
    sec
    sbc #MZMIN-1
    cmp #NENEMIES
    bcc pi_ne
    lda #NENEMIES
pi_ne:
    sta nenem

    lda #COL_WALL
    sta latwcol
    lda #COL_POST
    sta latpcol
    jsr draw_lattice
    jsr gen_init

    lda #0               ; the actors arrive when the maze is done
    sta spren
    lda #STATCOL         ; the status row gets its color band
    sta statbg
    +setupd play_build
    rts

; ---- the maze carves itself, BUILD_STEPS steps a frame ----
play_build:
    lda #BUILD_STEPS
    sta ptmp
pb_loop:
    jsr gm_step
    bcs play_start
    dec ptmp
    bne pb_loop
    rts

; ---- the maze is done: exit, actors, sprites, input ----
play_start:
    ; the exit: a portal in the right border wall
ps_exit:
    jsr rand8
    and #$0f
    cmp mzch
    bcs ps_exit
    asl                  ; cell row -> screen row (offy + 2*cy + 1)
    sec
    adc offy
    sta exrow
    tax
    jsr row_ptr
    ldy excol
    lda #CH_EXIT
    sta (scrlo),y
    lda #COL_EXIT
    sta (collo),y

    ; the worker starts in the top-left cell, facing right
    lda offx
    clc
    adc #1
    sta px
    lda offy
    clc
    adc #1
    sta py
    lda #1
    sta fdx
    lda #0
    sta fdy
    lda px
    sta tgc
    lda py
    sta tgr
    jsr set_target
    ldx #SP_RUN
    jsr spr_jump

    ; ra's cursor starts on the center post
    lda mzcw
    lsr
    asl
    clc
    adc offx
    sta kx
    lda mzch
    lsr
    asl
    clc
    adc offy
    sta ky
    lda #COL_HILITE
    jsr mark_slots
    lda kx
    sta tgc
    lda ky
    sta tgr
    jsr set_target
    ldx #SP_CUR
    jsr spr_jump

    lda #WHITE
    sta sprcol+SP_RUN
    sta sprcol+SP_SHOT
    lda #COL_HILITE      ; ra wears the sun's color
    sta sprcol+SP_CUR
    lda #COL_STING
    sta sprcol+SP_STING

    jsr place_relics     ; first: the enemies then avoid their cells
    jsr spawn_enemies

    ; input state: fire still held from the previous screen
    ; must be released before it can spin or shoot
    lda #0
    sta rheld
    sta cheld
    sta endflag
    sta s_on
    sta sx
    sta sy
    sta es_on
    sta cool
    sta rotflash
    lda #1
    sta cfheld
    sta rfheld
    +setupd play_update
    jmp upd_sprites      ; positions, shapes and enables now

; ============================================================
; maze geometry - the lattice is sized and placed from the
; cell counts in mzcw / mzch (the levels are squares, the
; menu backdrop is the full 19x11)
; ============================================================

; from mzcw/mzch: screen offsets, the exit column, the
; visited-index multiply table, ra's post bounds and the
; enemies' spawn half
set_maze:
    lda #19              ; offx = (39 - (2*cw+1)) / 2 = 19 - cw
    sec
    sbc mzcw
    sta offx
    lda #12              ; rows 1-23: offy = 12 - ch
    sec
    sbc mzch
    sta offy
    lda #0               ; multab[i] = i * mzcw
    tax
sm_mul:
    sta multab,x
    clc
    adc mzcw
    inx
    cpx #MZMAX
    bne sm_mul
    lda mzcw             ; the right border column holds the exit
    asl
    clc
    adc offx
    sta excol
    sec                  ; interior posts: offx+2 .. offx+2*cw-2
    sbc #2
    sta kmaxx
    lda offx
    clc
    adc #2
    sta kminx
    lda mzch
    asl
    clc
    adc offy
    sec
    sbc #2
    sta kmaxy
    lda offy
    clc
    adc #2
    sta kminy
    lda mzcw             ; enemies spawn on the right half
    lsr
    sta enhalf
    rts

; fill the lattice with sandstone in latwcol, the pivot posts
; (even local column and row) in latpcol
draw_lattice:
    lda offy
    sta ptmp
dl_fill:
    ldx ptmp
    jsr row_ptr
    lda mzcw
    asl
    sta lcnt
    inc lcnt             ; 2*cw+1 chars per lattice row
    ldy offx
dl_col:
    lda #CH_WALL
    sta (scrlo),y
    lda latwcol
    sta (collo),y
    iny
    dec lcnt
    bne dl_col
    inc ptmp
    lda mzch
    asl
    clc
    adc offy             ; the bottom lattice row
    cmp ptmp
    bcs dl_fill
    lda offy             ; post rows: offy, offy+2, ...
    sta ptmp
dl_prow:
    ldx ptmp
    jsr row_ptr
    lda mzcw
    asl
    clc
    adc offx
    tay                  ; post columns from the right edge down
    lda mzcw
    sta lcnt
    inc lcnt             ; cw+1 posts per post row
dl_pcol:
    lda #CH_POST
    sta (scrlo),y
    lda latpcol
    sta (collo),y
    dey
    dey
    dec lcnt
    bne dl_pcol
    inc ptmp
    inc ptmp
    lda mzch
    asl
    clc
    adc offy
    cmp ptmp
    bcs dl_prow
    rts

; ============================================================
; maze generation - recursive backtracker over the cells;
; the screen itself is the wall data structure
; ============================================================

; reset the generator: nothing visited, start on cell (0,0)
gen_init:
    ldx #0
    lda #0
gi_clr:
    sta visited,x
    inx
    cpx #NCELLS
    bne gi_clr
    lda #0
    sta gcx
    sta gcy
    sta gsp
    jsr gv_mark
    jmp carve_cell

; one generator step: carve toward a random unvisited
; neighbor, or back up one; C set when the maze is finished
gm_step:
    ; collect the unvisited neighbor directions
    lda #0
    sta gn
    ldx #0
gm_scan:
    stx gtd
    lda gcx
    clc
    adc dxtab,x
    sta gnx
    cmp mzcw             ; unsigned: -1 wraps to $ff and fails too
    bcs gm_next
    ldx gtd
    lda gcy
    clc
    adc dytab,x
    sta gny
    cmp mzch
    bcs gm_next
    ldx gny
    lda multab,x
    clc
    adc gnx
    tax
    lda visited,x
    bne gm_next
    ldx gn
    lda gtd
    sta gdlist,x
    inc gn
gm_next:
    ldx gtd
    inx
    cpx #4
    bne gm_scan
    lda gn
    beq gm_pop
    ; pick a random one of them
gm_pick:
    jsr rand8
    and #3
    cmp gn
    bcs gm_pick
    tax
    lda gdlist,x
    sta gtd
    ; push the current cell, open the wall, step through it
    ldx gsp
    lda gcx
    sta stackx,x
    lda gcy
    sta stacky,x
    inc gsp
    jsr carve_wall
    ldx gtd
    lda gcx
    clc
    adc dxtab,x
    sta gcx
    ldx gtd
    lda gcy
    clc
    adc dytab,x
    sta gcy
    jsr gv_mark
    jsr carve_cell
    clc
    rts
gm_pop:
    ; dead end: back up; empty stack = the maze is done
    lda gsp
    beq gm_done
    dec gsp
    ldx gsp
    lda stackx,x
    sta gcx
    lda stacky,x
    sta gcy
    clc
    rts
gm_done:
    sec
    rts

gen_maze_full:           ; the menu backdrop wants it all at once
    jsr gm_step
    bcc gen_maze_full
    rts

gv_mark:                 ; visited[gcy * mzcw + gcx] = 1
    ldx gcy
    lda multab,x
    clc
    adc gcx
    tax
    lda #1
    sta visited,x
    rts

carve_cell:              ; open the cell at (offx+2*gcx+1, offy+2*gcy+1)
    lda gcy
    asl
    sec
    adc offy
    tax
    jsr row_ptr
    lda gcx
    asl
    sec
    adc offx
    tay
    lda #CH_FLOOR
    sta (scrlo),y
    lda #BLACK
    sta (collo),y
    rts

carve_wall:              ; open the wall slot toward direction gtd
    ldx gtd
    lda gcy
    asl
    sec
    adc offy
    clc
    adc dytab,x
    tax
    jsr row_ptr
    ldx gtd
    lda gcx
    asl
    sec
    adc offx
    clc
    adc dxtab,x
    tay
    lda #CH_FLOOR
    sta (scrlo),y
    lda #BLACK
    sta (collo),y
    rts

dxtab: !byte 0, 0, $ff, 1        ; up, down, left, right
dytab: !byte $ff, 1, 0, 0

; ---- enemies: even index = scarab, odd = scorpion; random
; right-half cells, away from the worker's start ----
spawn_enemies:
    lda #0
    sta ei
sn_all:
    jsr spawn_one
    inc ei
    lda ei
    cmp nenem
    bne sn_all
    rts

spawn_one:               ; place enemy ei on a random free cell
sn_rx:
    jsr rand8
    and #$0f
    cmp mzcw
    bcs sn_rx
    cmp enhalf           ; keep to the right half
    bcc sn_rx
    asl
    sec
    adc offx             ; cell column -> screen column
    sta ttx
sn_ry:
    jsr rand8
    and #$0f
    cmp mzch
    bcs sn_ry
    asl
    sec
    adc offy
    sta tty              ; candidate screen row
    ldx tty
    jsr row_ptr
    ldy ttx
    lda (scrlo),y
    cmp #CH_FLOOR        ; only a carved cell will do...
    bne sn_rx
    lda ttx              ; ...without the worker on it...
    cmp px
    bne sn_free
    lda tty
    cmp py
    beq sn_rx
sn_free:
    jsr enemy_at         ; ...or another live enemy
    bcs sn_rx
    ldx ei
    lda ttx
    sta ex,x
    lda tty
    sta ey,x
    lda ei
    and #1               ; the type wears its own color
    tay
    lda etypecol,y
    sta sprcol+SP_EN,x
    jsr rand8
    and #3
    sta edir,x
    lda #0
    sta edead,x
    lda ttx              ; the sprite pops in on the cell
    sta tgc
    lda tty
    sta tgr
    jsr set_target
    lda ei
    clc
    adc #SP_EN
    tax
    jmp spr_jump

etypecol: !byte COL_SCARAB, COL_SCORP

; ============================================================
; the relics (relic order option) - numbered treasures on the
; maze cells; the worker must collect them in order before
; the portal will let him out
; ============================================================

; ---- scatter this level's relics over random cells: one
; more each level, 2 on level 1 up to 9 on level 8 ----
place_relics:
    lda #0
    sta rnext
    sta rcount
    sta ri
    lda opt_relic
    beq pl_done
    lda mzsize           ; level 1-8 -> 2-9 relics
    sec
    sbc #MZMIN-2
    sta rcount
pl_one:
    jsr rand8
    and #$0f
    cmp mzcw
    bcs pl_one
    asl                  ; cell column -> screen column
    sec
    adc offx
    sta ttx
pl_ry:
    jsr rand8
    and #$0f
    cmp mzch
    bcs pl_ry
    asl
    sec
    adc offy
    sta tty
    lda ttx              ; never on the worker's own starting cell...
    cmp px
    bne pl_free
    lda tty
    cmp py
    beq pl_one
pl_free:
    jsr relic_at         ; ...nor on a cell already holding one
    bcs pl_one
    ldx ri
    lda ttx
    sta rlx,x
    lda tty
    sta rly,x
    jsr draw_relic
    inc ri
    lda ri
    cmp rcount
    bne pl_one
pl_done:
    rts

; ---- stamp relic X on (ttx, tty): its order is its digit ----
draw_relic:
    txa
    clc
    adc #CH_RELIC
    pha
    ldx tty
    jsr row_ptr
    ldy ttx
    pla
    sta (scrlo),y
    lda #COL_RELIC
    sta (collo),y
    rts

; ---- C set when one of the ri placed relics sits on
; (ttx, tty) - the placement loop's duplicate check ----
relic_at:
    ldx ri
    beq rlk_no
rlk_loop:
    dex
    lda rlx,x
    cmp ttx
    bne rlk_next
    lda rly,x
    cmp tty
    beq rlk_yes
rlk_next:
    cpx #0
    bne rlk_loop
rlk_no:
    clc
    rts
rlk_yes:
    sec
    rts

; ---- the worker stepped onto a cell: if it holds the relic
; that is next in the order, it goes into his hands ----
take_relic:
    lda opt_relic
    beq tk_done
    ldx rnext
    cpx rcount
    bcs tk_done          ; all of them already in hand
    lda rlx,x
    cmp px
    bne tk_done
    lda rly,x
    cmp py
    bne tk_done
    ldx py               ; the cell goes back to plain corridor
    jsr row_ptr
    ldy px
    lda #CH_FLOOR
    sta (scrlo),y
    lda #BLACK
    sta (collo),y
    inc rnext
    lda #4               ; a white border blip marks the find
    sta bflash
    lda #WHITE
    sta bcolor
    lda #SFX_SELECT
    jmp sfx_play
tk_done:
    rts

; ---- C set when the portal will take the worker: always in
; the classic game, once every relic is his in relic mode ----
exit_open:
    lda opt_relic
    beq eo_yes
    lda rnext
    cmp rcount
    bcc eo_no
eo_yes:
    sec
    rts
eo_no:
    clc
    rts

; ---- C set when the char in A can be walked or flown
; through: the corridor floor and the relics lying on it ----
open_ch:
    cmp #CH_FLOOR
    beq oc_yes
    cmp #CH_RELIC        ; the relic digits sit on open floor
    bcc oc_no
    cmp #CH_RELIC+NRELIC
    bcs oc_no
oc_yes:
    sec
    rts
oc_no:
    clc
    rts

; ============================================================
; one frame of play
; ============================================================
play_update:
    jsr spr_restore      ; the maze under the actors, for the logic below
    inc tframe           ; the run clock: 50 frames = one second
    lda tframe
    cmp #50
    bne pu_clock
    lda #0
    sta tframe
    inc tsec
    lda tsec
    cmp #60
    bne pu_clock
    lda #0
    sta tsec
    inc tmin
    lda tmin
    cmp #100             ; the clock pegs at 99:59
    bne pu_clock
    lda #99
    sta tmin
pu_clock:
    lda cool             ; the spin recharge ticks down
    beq pu_nocool
    dec cool
pu_nocool:
    jsr upd_runner
    lda endflag
    bne pu_end
    jsr upd_shot
    jsr upd_enemies
    lda endflag
    bne pu_end
    jsr upd_sting
    lda endflag
    bne pu_end
    jsr upd_cursor
    jsr upd_flash
    jsr upd_status
    jsr upd_goal
    jsr upd_clock
    jmp upd_sprites
pu_end:
    pha
    jsr upd_sprites      ; the actors stay on screen for the fade
    pla
    cmp #1
    beq pu_win
    lda #SFX_LOSE
    jsr sfx_play
    +fadeto lose_init
pu_win:
    lda #SFX_WIN
    jsr sfx_play
    lda mzsize           ; the last level won: the blessing is earned
    cmp #MZMAX
    bcs pw_final
    inc mzsize           ; otherwise the next maze is one cell bigger
    +fadeto play_init
pw_final:
    +fadeto win_init

; ---- player 1: walk the corridors, one cell per step ----
upd_runner:
    jsr read_joy
    and #$0f
    sta rdir
    bne ur_held
    lda #0
    sta rheld
    rts
ur_held:
    lda rheld
    beq ur_first
    dec rtimer
    beq ur_rep
    rts
ur_rep:
    lda #REP_PERIOD
    sta rtimer
    jmp ur_move
ur_first:
    lda #1
    sta rheld
    lda #REP_HOLD
    sta rtimer
ur_move:
    ; decode the direction; it also becomes the gun's facing
    ldx px
    ldy py
    lda rdir
    lsr
    bcs ur_up
    lsr
    bcs ur_down
    lsr
    bcs ur_left
    inx                  ; right
    lda #1
    sta fdx
    lda #0
    sta fdy
    jmp ur_try
ur_up:
    dey
    lda #0
    sta fdx
    lda #$ff
    sta fdy
    jmp ur_try
ur_down:
    iny
    lda #0
    sta fdx
    lda #1
    sta fdy
    jmp ur_try
ur_left:
    dex
    lda #$ff
    sta fdx
    lda #0
    sta fdy
ur_try:
    stx ttx
    sty tty
    ldx tty
    jsr row_ptr
    ldy ttx
    lda (scrlo),y
    cmp #CH_EXIT
    beq ur_exit
    jsr open_ch
    bcc ur_stop          ; a wall or a post: blocked
    jsr enemy_at         ; walking into an enemy still hurts
    bcs ur_dead
    lda es_on            ; and so does the venom sting
    beq ur_go
    lda ttx
    cmp esx
    bne ur_go
    lda tty
    cmp esy
    beq ur_dead
ur_go:
    lda ttx
    sta px
    lda tty
    sta py
    jmp take_relic       ; the cell may hold the next relic
ur_stop:
    rts
ur_exit:
    jsr exit_open
    bcc ur_sealed
    lda #1
    sta endflag
    rts
ur_sealed:               ; relics still out there: the portal is shut
    jmp deny_blip
ur_dead:
    lda #2
    sta endflag
    rts

; ---- the optional gun: one straight-flying bullet sprite ----
upd_shot:
    lda s_on
    beq sh_spawn
    lda sx               ; one step along its heading
    clc
    adc sdx
    sta ttx
    lda sy
    clc
    adc sdy
    sta tty
    ldx tty
    jsr row_ptr
    ldy ttx
    lda (scrlo),y
    jsr open_ch
    bcs sh_open
    lda #0               ; a wall (or the portal) stops it
    sta s_on
    jmp sh_spawn
sh_open:
    jsr enemy_at
    bcc sh_fly
    jsr kill_idx         ; X = the victim
    lda #0
    sta s_on
    jmp sh_spawn
sh_fly:
    lda ttx
    sta sx
    lda tty
    sta sy
sh_spawn:
    lda opt_shoot        ; fire spawns a bullet (edge detected)
    beq sh_done
    lda joyb             ; read_joy ran in upd_runner this frame
    and #JOY_FIRE
    beq sh_frel
    lda rfheld
    bne sh_done
    lda #1
    sta rfheld
    lda s_on
    bne sh_done          ; one bullet at a time
    lda px
    sta sx
    lda py
    sta sy
    lda fdx
    sta sdx
    lda fdy
    sta sdy
    lda #1
    sta s_on
    lda #SFX_SHOT
    jmp sfx_play
sh_frel:
    lda #0
    sta rfheld
sh_done:
    rts

; ---- enemy X was hit: it starts its respawn timer ----
kill_idx:
    lda #RESPAWN_TIME
    sta edead,x
    lda #4               ; white border blip
    sta bflash
    lda #WHITE
    sta bcolor
    lda #SFX_HIT
    jmp sfx_play

; ---- is a live enemy standing on (ttx, tty)?
; returns C set + its index in X when one is ----
enemy_at:
    ldx #0
ea_loop:
    lda edead,x
    bne ea_next
    lda ex,x
    cmp ttx
    bne ea_next
    lda ey,x
    cmp tty
    bne ea_next
    sec
    rts
ea_next:
    inx
    cpx nenem
    bne ea_loop
    clc
    rts

; ---- player 2: ra's corner cursor + the wall spin ----
upd_cursor:
    jsr read_joy2
    sta j2bits
    and #$0f
    sta cdir
    bne uc_held
    lda #0
    sta cheld
    jmp uc_fire
uc_held:
    lda cheld
    beq uc_first
    dec ctimer
    beq uc_rep
    jmp uc_fire
uc_rep:
    lda #CREP_PERIOD
    sta ctimer
    jmp uc_move
uc_first:
    lda #1
    sta cheld
    lda #CREP_HOLD
    sta ctimer
uc_move:
    ldx kx
    ldy ky
    lda cdir
    lsr
    bcs uc_up
    lsr
    bcs uc_down
    lsr
    bcs uc_left
    cpx kmaxx            ; right: the interior posts end here
    bcs uc_fire
    inx
    inx
    jmp uc_go
uc_up:
    cpy kminy
    bcc uc_fire
    beq uc_fire
    dey
    dey
    jmp uc_go
uc_down:
    cpy kmaxy
    bcs uc_fire
    iny
    iny
    jmp uc_go
uc_left:
    cpx kminx
    bcc uc_fire
    beq uc_fire
    dex
    dex
uc_go:
    stx ttx
    sty tty
    lda #COL_WALL        ; the old corner's walls lose the highlight
    jsr mark_slots
    lda #0               ; a spin flash does not follow the cursor
    sta rotflash
    lda ttx
    sta kx
    lda tty
    sta ky
    lda #COL_HILITE      ; show the walls a spin here would move
    jsr mark_slots
    lda #SFX_CURSOR
    jsr sfx_play
uc_fire:
    lda j2bits
    and #JOY_FIRE
    beq uc_frel
    lda cfheld
    bne uc_done
    lda #1
    sta cfheld
    jmp do_rotate        ; its rts returns to play_update's caller
uc_frel:
    lda #0
    sta cfheld
uc_done:
    rts

; ---- spin the four wall slots around post (kx, ky) by 90
; degrees clockwise; denied while anyone stands in them or
; while the optional cooldown is still recharging ----
do_rotate:
    lda opt_cool
    beq dr_ready
    lda cool
    beq dr_ready
dr_deny:
    jmp deny_blip        ; still recharging / a slot is taken
dr_ready:
    lda kx               ; nobody may stand in the four slots
    sta ttx
    ldx ky
    dex
    stx tty
    jsr slot_occ
    bcs dr_deny
    ldx ky
    inx
    stx tty
    jsr slot_occ
    bcs dr_deny
    lda ky
    sta tty
    ldx kx
    dex
    stx ttx
    jsr slot_occ
    bcs dr_deny
    ldx kx
    inx
    stx ttx
    jsr slot_occ
    bcs dr_deny
    ldx ky               ; gather the four slot chars
    dex
    jsr row_ptr
    ldy kx
    lda (scrlo),y
    sta nch
    ldx ky
    inx
    jsr row_ptr
    ldy kx
    lda (scrlo),y
    sta sch
    ldx ky
    jsr row_ptr
    ldy kx
    dey
    lda (scrlo),y
    sta wch
    iny
    iny
    lda (scrlo),y
    sta ech
    ; clockwise: north<-west, east<-north, south<-east, west<-south
    ldx ky
    dex
    jsr row_ptr
    ldy kx
    lda wch
    jsr put_slot
    ldx ky
    inx
    jsr row_ptr
    ldy kx
    lda ech
    jsr put_slot
    ldx ky
    jsr row_ptr
    ldy kx
    dey
    lda sch
    jsr put_slot
    iny
    iny
    lda nch
    jsr put_slot
    lda #10              ; the moved pieces flash white
    sta rotflash
    lda opt_cool         ; the spin starts the recharge
    beq dr_nocool
    lda #COOL_TIME
    sta cool
dr_nocool:
    lda #SFX_ROTATE
    jmp sfx_play
; ---- red border blip + buzz: a denied spin, or the worker
; knocking on a portal the relics have not opened yet ----
deny_blip:
    lda #6
    sta bflash
    lda #RED
    sta bcolor
    lda #SFX_DENY
    jmp sfx_play

slot_occ:                ; C set when someone stands on (ttx, tty)
    lda px
    cmp ttx
    bne so_norun
    lda py
    cmp tty
    beq so_yes
so_norun:
    jsr enemy_at
    bcs so_yes
    lda s_on
    beq so_nosht
    lda sx
    cmp ttx
    bne so_nosht
    lda sy
    cmp tty
    beq so_yes
so_nosht:
    lda es_on            ; the sting blocks a spin too
    beq so_no
    lda esx
    cmp ttx
    bne so_no
    lda esy
    cmp tty
    beq so_yes
so_no:
    clc
    rts
so_yes:
    sec
    rts

put_slot:                ; write char A at (scrlo),y + matching color
    sta (scrlo),y
    cmp #CH_WALL
    beq ps_wall
    lda #BLACK
    sta (collo),y
    rts
ps_wall:
    lda #COL_WALL
    sta (collo),y
    rts

; ---- paint the four slots around the cursor post with the
; color in A - only wall blocks change, so the highlight marks
; exactly the pieces a spin would move (floors stay black) ----
mark_slots:
    sta hlcol
    ldx ky               ; north
    dex
    jsr row_ptr
    ldy kx
    jsr mark_one
    ldx ky               ; south
    inx
    jsr row_ptr
    ldy kx
    jsr mark_one
    ldx ky               ; west
    jsr row_ptr
    ldy kx
    dey
    jsr mark_one
    iny                  ; east: falls through to mark it
    iny
mark_one:
    lda (scrlo),y
    cmp #CH_WALL
    bne mo_skip
    lda hlcol
    sta (collo),y
mo_skip:
    rts

; ---- the enemies: staggered random walkers ----
upd_enemies:
    lda #0
    sta ei
ue_loop:
    ldx ei
    lda edead,x
    beq ue_alive
    dec edead,x          ; shot down: waiting to respawn
    bne ue_next
    jsr spawn_one        ; the timer ran out: back on a fresh cell
    jmp ue_next
ue_alive:
    lda framectr
    clc
    adc estag,x
    and #7               ; each enemy steps every 8th frame
    bne ue_next
    jsr enemy_step
    lda endflag
    bne ue_out
    jsr try_sting
ue_next:
    inc ei
    lda ei
    cmp nenem
    bne ue_loop
ue_out:
    rts

estag: !byte 0, 2, 4, 6

enemy_step:
    jsr rand8            ; 1 in 4: wander off in a new direction
    and #3
    beq es_newdir
    ldx ei
    lda edir,x
    jsr etry_dir
    bcc es_done
es_newdir:
    lda #8
    sta etries
es_pick:
    jsr rand8
    and #3
    jsr etry_dir
    bcc es_done
    dec etries           ; walled in on all sides: sit this one out
    bne es_pick
es_done:
    rts

etry_dir:                ; A = direction; C clear when it moved (or won)
    sta etd
    tax
    ldy ei
    lda ex,y
    clc
    adc dxtab,x
    sta ttx
    lda ey,y
    clc
    adc dytab,x
    sta tty
    lda px               ; onto the worker: the level is over
    cmp ttx
    bne en_norun
    lda py
    cmp tty
    bne en_norun
    lda #2
    sta endflag
    clc
    rts
en_norun:
    ldx tty              ; anything but open floor blocks it
    jsr row_ptr
    ldy ttx
    lda (scrlo),y
    jsr open_ch
    bcs en_open
    sec
    rts
en_open:
    jsr enemy_at         ; another enemy blocks it
    bcc en_nofoe
    sec
    rts
en_nofoe:
    lda s_on             ; walking into the bullet hurts too
    beq en_move
    lda sx
    cmp ttx
    bne en_move
    lda sy
    cmp tty
    bne en_move
    lda #0
    sta s_on
    ldx ei
    jsr kill_idx
    clc
    rts
en_move:
    ldx ei
    lda ttx
    sta ex,x
    lda tty
    sta ey,x
    lda etd
    sta edir,x
    clc
    rts

; ---- a scorpion (odd index) spits a venom sting when it
; lines up with the worker; one sting flies at a time ----
try_sting:
    lda ei
    and #1
    beq ts_no            ; scarabs do not shoot
    lda es_on
    bne ts_no
    jsr rand8            ; menacing, not machine-gun constant
    and #3
    bne ts_no
    ldx ei
    lda ex,x
    cmp px
    beq ts_col
    lda ey,x
    cmp py
    beq ts_row
ts_no:
    rts
ts_col:                  ; same column: the sting flies vertically
    lda #0
    sta esdx
    ldy #1
    lda py
    cmp ey,x
    bcs ts_cgo
    ldy #$ff
ts_cgo:
    sty esdy
    jmp ts_fire
ts_row:                  ; same row: horizontally
    lda #0
    sta esdy
    ldy #1
    lda px
    cmp ex,x
    bcs ts_rgo
    ldy #$ff
ts_rgo:
    sty esdx
ts_fire:
    lda ex,x
    sta esx
    sta tgc
    lda ey,x
    sta esy
    sta tgr
    jsr set_target       ; the sprite pops in on the scorpion,
    ldx #SP_STING        ; not gliding over from the last sting
    jsr spr_jump
    lda #1
    sta es_on
    lda #SFX_SHOT
    jmp sfx_play

; ---- the sting flies a char every other frame; a wall
; swallows it, the worker dies on it ----
upd_sting:
    lda es_on
    beq ust_done
    lda framectr
    and #1
    bne ust_done
    lda esx
    clc
    adc esdx
    sta ttx
    lda esy
    clc
    adc esdy
    sta tty
    lda px               ; onto the worker: the level is over
    cmp ttx
    bne ust_norun
    lda py
    cmp tty
    bne ust_norun
    lda #2
    sta endflag
    rts
ust_norun:
    ldx tty
    jsr row_ptr
    ldy ttx
    lda (scrlo),y
    jsr open_ch
    bcs ust_fly
    lda #0               ; a wall swallows it
    sta es_on
    rts
ust_fly:
    lda ttx
    sta esx
    lda tty
    sta esy
ust_done:
    rts

; ---- per-frame flashes: the portal spins and blinks, the
; freshly spun walls flash white, the cursor shows the
; recharge state on its own color ----
upd_flash:
    jsr upd_portal       ; cycle the portal glyph
    ldx exrow
    jsr row_ptr
    ldy excol
    jsr exit_open
    bcc uf_exlock
    lda framectr
    and #8
    bne uf_exw
    lda #COL_EXIT
    jmp uf_exset
uf_exw:
    lda #WHITE
    jmp uf_exset
uf_exlock:
    lda #DGREY           ; sealed while a relic is still missing
uf_exset:
    sta (collo),y
    lda rotflash         ; the spun walls flash, then re-highlight
    beq uf_norf
    dec rotflash
    bne uf_white
    lda #COL_HILITE
    jmp uf_mark
uf_white:
    lda #WHITE
uf_mark:
    jsr mark_slots
uf_norf:
    lda opt_cool         ; the cursor dims red while recharging
    beq uf_hot
    lda cool
    beq uf_hot
    lda #RED
    jmp uf_cset
uf_hot:
    lda #COL_HILITE
uf_cset:
    sta sprcol+SP_CUR
    ; fall through: the relic he is after next pulses white
relic_blink:
    lda opt_relic
    beq rb_done
    ldx rnext
    cpx rcount
    bcs rb_done
    lda rlx,x
    sta ptmp
    lda rly,x
    tax
    jsr row_ptr
    ldy ptmp
    lda framectr
    and #8
    bne rb_white
    lda #COL_RELIC
    jmp rb_set
rb_white:
    lda #WHITE
rb_set:
    sta (collo),y
rb_done:
    rts

; ---- status row: the spin recharge readout (cooldown option)
; "wait" + a bar draining pixel by pixel, "ready" after ----
upd_status:
    lda opt_cool
    bne us_show
    rts
us_show:
    lda cool
    beq us_ready
    +prtext 0, 17, LRED, txt_wait, 4
    lda cool             ; pixels left: cool / 2 = 0-80
    lsr
    sta ptmp
    ldx #0
us_bar:
    lda ptmp
    beq us_empty
    cmp #8
    bcc us_part
    sec                  ; a full cell, and onward
    sbc #8
    sta ptmp
    lda #$a0
    jmp us_put
us_part:
    clc                  ; 1-7 pixels: one of the bar chars
    adc #CH_BAR-1
    ldy #0
    sty ptmp
    jmp us_put
us_empty:
    lda #$20
us_put:
    sta SCREEN+23,x      ; bar cells: row 0, columns 23-32
    lda #LRED
    sta COLRAM+23,x
    inx
    cpx #10
    bne us_bar
    rts
us_ready:
    +prtext 0, 17, LGREEN, txt_ready, 5
    lda #$20             ; clear the bar area
    ldx #9
us_clr:
    sta SCREEN+23,x
    dex
    bpl us_clr
    rts

; ---- relic mode's readout in the goal corner: relics in
; hand / relics on the level, next to the portal glyph; green
; once the last one is his ----
upd_goal:
    lda opt_relic
    bne ug_show
    rts
ug_show:
    lda rnext
    ora #$30
    sta SCREEN+34
    lda #$2f             ; '/'
    sta SCREEN+35
    lda rcount
    ora #$30
    sta SCREEN+36
    lda #$20
    sta SCREEN+37
    lda #CH_EXIT
    sta SCREEN+38
    jsr exit_open
    lda #LRED
    bcc ug_col
    lda #LGREEN
ug_col:
    ldx #4
ug_loop:
    sta COLRAM+34,x
    dex
    bpl ug_loop
    rts

; ---- the run clock, live on the status row ----
upd_clock:
    lda tmin
    jsr two_digits
    stx SCREEN+11        ; clock cells: row 0, columns 11-15
    sta SCREEN+12
    lda #$3a             ; ':'
    sta SCREEN+13
    lda tsec
    jsr two_digits
    stx SCREEN+14
    sta SCREEN+15
    ldx #4
ucl_col:
    lda #LGREY
    sta COLRAM+11,x
    dex
    bpl ucl_col
    rts

; ---- drive the eight actors from the grid state, then hand
; them to the software sprite layer ----
upd_sprites:
    lda framectr
    lsr
    lsr
    lsr
    sta frame8
    ; the worker glides 2 pixels a frame
    lda px
    sta tgc
    lda py
    sta tgr
    jsr set_target
    lda #2
    sta gspd
    ldx #SP_RUN
    jsr spr_glide
    ; the cursor glides 4 (its step is two cells)
    lda kx
    sta tgc
    lda ky
    sta tgr
    jsr set_target
    lda #4
    sta gspd
    ldx #SP_CUR
    jsr spr_glide
    ; the bullet snaps cell to cell
    lda sx
    sta tgc
    lda sy
    sta tgr
    jsr set_target
    ldx #SP_SHOT
    jsr spr_jump
    ; the sting glides 4: a char every other frame, smoothly
    lda esx
    sta tgc
    lda esy
    sta tgr
    jsr set_target
    lda #4
    sta gspd
    ldx #SP_STING
    jsr spr_glide
    ; the enemies glide 1
    lda #1
    sta gspd
    ldx #0
us_en:
    stx ptmp
    lda ex,x
    sta tgc
    lda ey,x
    sta tgr
    jsr set_target
    lda ptmp
    clc
    adc #SP_EN
    tax
    jsr spr_glide
    ldx ptmp
    inx
    cpx nenem
    bne us_en
    ; shapes: the worker bobs, each enemy waves on its own beat
    lda frame8
    and #1
    clc
    adc #SHP_RUN
    sta sprshape+SP_RUN
    lda #SHP_CUR
    sta sprshape+SP_CUR
    lda #SHP_SHOT
    sta sprshape+SP_SHOT
    lda #SHP_STING
    sta sprshape+SP_STING
    ldx #0
us_shape:
    txa
    clc
    adc frame8
    and #1
    sta rtmp
    txa
    and #1               ; even index = scarab, odd = scorpion
    beq us_scar
    lda #SHP_ENB
    bne us_seta          ; always taken
us_scar:
    lda #SHP_ENA
us_seta:
    clc
    adc rtmp
    sta sprshape+SP_EN,x
    inx
    cpx nenem
    bne us_shape
    ; visible: worker + cursor, bullet, sting, live enemies
    lda #%00000011
    ldy s_on
    beq us_nosht
    ora #%00000100
us_nosht:
    ldy es_on
    beq us_nostg
    ora #%10000000
us_nostg:
    sta rtmp
    ldx #0
us_alive:
    lda edead,x
    bne us_dead
    lda rtmp
    ora ebit,x
    sta rtmp
us_dead:
    inx
    cpx nenem
    bne us_alive
    lda rtmp
    sta spren
    jmp spr_draw

ebit: !byte 8, 16, 32, 64

; ---- play texts ----
txt_level: !scr "level"
txt_goal:  !scr "exit "
           !byte CH_EXIT
txt_goale:
txt_hint:  !scr "worker: joy2/wasd  ra: joy1/ijkl"
txt_hinte:
txt_wait:  !scr "wait"
txt_ready: !scr "ready"

; ---- play variables ----
!ifdef AUTOLEVEL {       ; test builds may boot into a later level
mzsize:  !byte MZMIN-1+AUTOLEVEL
} else {
mzsize:  !byte MZMIN     ; this level's cells per side (4-11)
}
mzcw:    !byte 0         ; lattice cells across / down
mzch:    !byte 0
offx:    !byte 0         ; screen offset of the lattice
offy:    !byte 0
excol:   !byte 0         ; screen column of the right border wall
enhalf:  !byte 0         ; enemies spawn from this cell column
nenem:   !byte 0         ; live enemy slots this level (1-4)
kminx:   !byte 0         ; ra's interior post bounds
kmaxx:   !byte 0
kminy:   !byte 0
kmaxy:   !byte 0
px:      !byte 0         ; worker position (screen col / row)
py:      !byte 0
fdx:     !byte 0         ; worker facing: the gun aims this way
fdy:     !byte 0
kx:      !byte 0         ; corner cursor position (post col / row)
ky:      !byte 0
exrow:   !byte 0         ; screen row of the exit portal
endflag: !byte 0         ; 0 = playing, 1 = escaped, 2 = caught
cool:    !byte 0         ; spin recharge frames left (cooldown option)
rotflash:!byte 0         ; frames the freshly spun walls stay white
rcount:  !byte 0         ; relics on this level (relic order option)
rnext:   !byte 0         ; the one he must pick up next
ri:      !byte 0         ; relic placement loop index
s_on:    !byte 0         ; bullet in flight?
sx:      !byte 0         ; bullet position and heading
sy:      !byte 0
sdx:     !byte 0
sdy:     !byte 0
es_on:   !byte 0         ; venom sting in flight?
esx:     !byte 0         ; sting position and heading
esy:     !byte 0
esdx:    !byte 0
esdy:    !byte 0
rheld:   !byte 0         ; worker direction repeat state
rtimer:  !byte 0
rdir:    !byte 0
rfheld:  !byte 0         ; worker fire edge detection state
cheld:   !byte 0         ; cursor direction repeat state
ctimer:  !byte 0
cdir:    !byte 0
cfheld:  !byte 0         ; cursor fire edge detection state
j2bits:  !byte 0
ptmp:    !byte 0         ; scratch
lcnt:    !byte 0         ; draw_lattice column counter
ttx:     !byte 0         ; move target (col / row)
tty:     !byte 0
nch:     !byte 0         ; the four slot chars around the cursor
ech:     !byte 0
sch:     !byte 0
wch:     !byte 0
hlcol:   !byte 0         ; mark_slots color parameter
latwcol: !byte 0         ; draw_lattice colors: walls, posts
latpcol: !byte 0
tframe:  !byte 0         ; run clock: frame, second, minute
tsec:    !byte 0
tmin:    !byte 0
frame8:  !byte 0         ; framectr / 8: the animation beat
ei:      !byte 0         ; enemy loop index
etries:  !byte 0
etd:     !byte 0
gcx:     !byte 0         ; maze generator state
gcy:     !byte 0
gsp:     !byte 0
gn:      !byte 0
gtd:     !byte 0
gnx:     !byte 0
gny:     !byte 0
gdlist:  !fill 4, 0
multab:  !fill MZMAX, 0  ; row * mzcw for the visited index
ex:      !fill NENEMIES, 0   ; enemy positions and headings
ey:      !fill NENEMIES, 0
edir:    !fill NENEMIES, 0
edead:   !fill NENEMIES, 0   ; respawn countdown, 0 = alive
rlx:     !fill NRELIC, 0     ; relic positions (screen col / row)
rly:     !fill NRELIC, 0

; ---- maze generator buffers ----
visited: !fill NCELLS, 0
stackx:  !fill NCELLS, 0
stacky:  !fill NCELLS, 0

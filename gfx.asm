; -----------------------------------------------------------
; gfx.asm - the graphics layer:
;   - the ROM font (128 chars, the TED inverts the rest in
;     hardware) is copied into RAM and a handful of custom
;     tiles are stamped over unused graphic codes (sandstone
;     wall, pivot post, the animated exit portal, the 1/8-step
;     cooldown bar)
;   - software sprites: every actor lives on the char grid,
;     its 8x8 shape glides toward the cell a few pixels a
;     frame (the worker bobs, the enemies wave); each frame
;     the shape is shifted to its pixel offset, composed over
;     the maze glyphs it covers into dynamic chars and those
;     are stamped on the screen; the covered cells are put
;     back before the next frame's game logic reads the maze
;   - fade to black: the transition between two screens, one
;     luminance step per pass
; -----------------------------------------------------------

; ---- one-time setup: font to RAM, custom tiles, TED ----
gfx_init:
    lda #>CHARROM        ; the uppercase set: 128 chars, 1 KB
    sta txthi
    lda #>CHARSET
    sta scrhi
    lda #0
    sta txtlo
    sta scrlo
    ldx #4
gc_page:
    ldy #0
gc_byte:
    lda (txtlo),y
    sta (scrlo),y
    iny
    bne gc_byte
    inc txthi
    inc scrhi
    dex
    bne gc_page
    ; the brick wall + the pivot post (two consecutive codes)
    ldx #15
gc_tiles:
    lda tile_gfx,x
    sta CHARSET+CH_WALL*8,x
    dex
    bpl gc_tiles
    ; the portal starts on frame 0
    ldx #7
gc_portal:
    lda portal_gfx,x
    sta CHARSET+CH_EXIT*8,x
    dex
    bpl gc_portal
    ; the seven bar cells: 1-7 pixels filled from the left
    ldx #0
    ldy #0
gc_bar:
    lda barmask,x
    sta rtmp
    lda #8
    sta rtmp2
gc_bar8:
    lda rtmp
    sta CHARSET+CH_BAR*8,y
    iny
    dec rtmp2
    bne gc_bar8
    inx
    cpx #7
    bne gc_bar
    ; the shift tables: for every shift 1-7 and byte, the bits
    ; that stay in the left char and those that spill right
    lda #<SHTAB
    sta scrlo
    sta collo
    lda #>SHTAB
    sta scrhi
    clc
    adc #1
    sta colhi
    lda #1
    sta scnt
gs_tab:
    ldy #0
gs_byte:
    sty stmp
    lda #0
    sta bgmask
    ldx scnt
gs_shift:
    lsr stmp
    ror bgmask
    dex
    bne gs_shift
    lda stmp
    sta (scrlo),y
    lda bgmask
    sta (collo),y
    iny
    bne gs_byte
    inc scrhi
    inc scrhi
    inc colhi
    inc colhi
    inc scnt
    lda scnt
    cmp #8
    bne gs_tab
    ; TED: 128 chars + hardware inverse, char data from RAM
    lda TED_CTL2
    and #$7f
    sta TED_CTL2
    lda TED_CHR
    and #%11111011
    sta TED_CHR
    lda #((>CHARSET) & $fc)
    sta TED_CHRB
    rts

; ---- cycle the portal glyph: 4 frames, one every 8 frames;
; rewriting the definition animates every portal on screen ----
upd_portal:
    lda framectr
    and #7
    bne up_done
    lda framectr
    and #$18             ; (frame index) * 8 = data offset
    tay
    ldx #0
up_copy:
    lda portal_gfx,y
    sta CHARSET+CH_EXIT*8,x
    iny
    inx
    cpx #8
    bne up_copy
up_done:
    rts

; ============================================================
; software sprite engine - positions are screen pixels:
; x 0-319 (sprxl/sprxh), y 0-199 (spry), cell (0,0) top-left
; ============================================================

; grid cell (tgc, tgr) -> pixel target tgxl/tgxh, tgy
set_target:
    lda #0
    sta tgxh
    lda tgc
    asl
    rol tgxh
    asl
    rol tgxh
    asl
    rol tgxh
    sta tgxl
    lda tgr
    asl
    asl
    asl
    sta tgy
    rts

; actor X snaps straight onto the target
spr_jump:
    lda tgxl
    sta sprxl,x
    lda tgxh
    sta sprxh,x
    lda tgy
    sta spry,x
    rts

; actor X slides gspd pixels per axis toward the target; the
; actors re-target every frame, so the distance always fits in
; a signed byte and a step never overshoots
spr_glide:
    lda tgxl
    sec
    sbc sprxl,x
    sta dtmp
    lda tgxh
    sbc sprxh,x          ; the high byte only carries the sign
    lda dtmp
    beq sg_y
    bmi sg_left
    cmp gspd             ; rightward: step = min(distance, speed)
    bcc sg_rgo
    lda gspd
sg_rgo:
    clc
    adc sprxl,x
    sta sprxl,x
    bcc sg_y
    inc sprxh,x
    jmp sg_y
sg_left:
    eor #$ff             ; leftward: the same on the distance
    clc
    adc #1
    cmp gspd
    bcc sg_lgo
    lda gspd
sg_lgo:
    sta dtmp
    lda sprxl,x
    sec
    sbc dtmp
    sta sprxl,x
    bcs sg_y
    dec sprxh,x
sg_y:
    lda tgy
    sec
    sbc spry,x
    beq sg_done
    bmi sg_up
    cmp gspd
    bcc sg_dgo
    lda gspd
sg_dgo:
    clc
    adc spry,x
    sta spry,x
    rts
sg_up:
    eor #$ff
    clc
    adc #1
    cmp gspd
    bcc sg_ugo
    lda gspd
sg_ugo:
    sta dtmp
    lda spry,x
    sec
    sbc dtmp
    sta spry,x
sg_done:
    rts

;   a shape byte shifted right by s: SHTAB + (s-1)*512 holds the
;   left char's bits by byte, the next page the right char's
SHTAB = CHARSET + $400

!macro compose {         ; one row of the dynamic char
    lda (bgptr),y
    eor bgmask
    ora (txtlo),y
    sta (dynptr),y
    iny
}

; ---- lift the actors off the screen: every cell spr_draw
; stamped gets its char and color back, last stamped first,
; so overlapping actors unwind correctly ----
spr_restore:
    ldx ncells
    beq sr_done
sr_loop:
    dex
    lda sv_lo,x
    sta scrlo
    sta collo
    lda sv_hi,x
    sta scrhi
    clc
    adc #COLOFF
    sta colhi
    ldy #0
    lda sv_ch,x
    sta (scrlo),y
    lda sv_col,x
    sta (collo),y
    cpx #0
    bne sr_loop
    stx ncells
sr_done:
    rts

; ---- stamp every enabled actor: the shape shifted to its
; pixel offset covers up to four cells; each gets a dynamic
; char holding the maze glyph underneath or-ed with the
; shape's slice (the cursor covers its cell instead), painted
; in the actor's color ----
spr_draw:
    lda #0
    sta ncells
    sta dynnext
    sta sdi
sd_actor:
    ldx sdi
    lda spren
    and sprbit,x
    bne sd_on
    jmp sd_next
sd_on:
    ; cell and pixel offset from the position
    lda sprxl,x
    and #7
    sta sox
    lda sprxl,x
    lsr
    lsr
    lsr
    ldy sprxh,x
    beq sd_xlo
    ora #$20
sd_xlo:
    sta scx
    lda spry,x
    and #7
    sta soy
    lda spry,x
    lsr
    lsr
    lsr
    sta scy
    lda sprcol,x
    sta scol
    lda sprmode,x
    sta smode
    lda sprshape,x
    asl
    asl
    asl
    clc
    adc #<shapes
    sta shptr
    lda #>shapes
    adc #0
    sta shptr+1
    ; the 16-row block of the two columns: the rows above and
    ; below the shape are blank...
    lda #0
    ldy soy
    beq sd_ztop_done
sd_ztop:
    dey
    sta blkl,y
    sta blkr,y
    bne sd_ztop
sd_ztop_done:
    ldy soy
sd_zbot:
    sta blkl+8,y         ; rows soy+8 .. 15
    sta blkr+8,y
    iny
    cpy #8
    bne sd_zbot
    ; ...and the shape's rows land soy down, split by sox into
    ; the two columns through the shift tables
    ldx soy
    lda sox
    beq sd_noshift
    sec
    sbc #1
    asl                  ; two pages per shift amount
    clc
    adc #>SHTAB
    sta shl+1
    clc
    adc #1
    sta shr+1
    lda #0
    sta shl
    sta shr
sd_srow:
    txa
    sec
    sbc soy
    tay
    lda (shptr),y
    tay
    lda (shl),y
    sta blkl,x
    lda (shr),y
    sta blkr,x
    inx
    txa
    sec
    sbc soy
    cmp #8
    bne sd_srow
    jmp sd_quads
sd_noshift:
    ldy #0
sd_crow:
    lda (shptr),y
    sta blkl,x
    lda #0
    sta blkr,x
    inx
    iny
    cpy #8
    bne sd_crow
sd_quads:
    ; the up to four cells the block covers
    lda #0
    sta sq
sd_quad:
    ldx sq
    lda qdx,x
    beq sd_qok1
    lda sox              ; aligned in x: no right column
    bne sd_qok1
    jmp sd_qnext
sd_qok1:
    lda qdy,x
    beq sd_qok2
    lda soy              ; aligned in y: no bottom row
    bne sd_qok2
    jmp sd_qnext
sd_qok2:
    lda qsrc_lo,x
    sta txtlo
    lda qsrc_hi,x
    sta txthi
    lda scy
    clc
    adc qdy,x
    tax
    jsr row_ptr
    ldx sq
    lda scx
    clc
    adc qdx,x
    tay
    ; remember the cell for spr_restore
    ldx ncells
    tya
    clc
    adc scrlo
    sta sv_lo,x
    lda scrhi
    adc #0
    sta sv_hi,x
    lda (scrlo),y
    sta sv_ch,x
    sta bgcode
    lda (collo),y
    sta sv_col,x
    inc ncells
    ; the glyph underneath (or eight zero bytes when the actor
    ; covers its cell); an inverse code means the glyph flipped
    lda #0
    sta bgmask
    lda smode
    bne sd_nobg
    lda bgcode
    bpl sd_bgpos
    lda #$ff
    sta bgmask
sd_bgpos:
    lda bgcode
    and #$7f
    sta stmp
    lda #0
    sta bgptr+1
    lda stmp
    asl
    rol bgptr+1
    asl
    rol bgptr+1
    asl
    rol bgptr+1
    sta bgptr
    lda bgptr+1
    clc
    adc #>CHARSET
    sta bgptr+1
    jmp sd_compose
sd_nobg:
    lda #<zero8
    sta bgptr
    lda #>zero8
    sta bgptr+1
sd_compose:
    ; the dynamic char: glyph | shape slice
    lda dynnext
    asl
    asl
    asl
    sta dynptr
    lda #>(CHARSET+CH_DYN*8)
    sta dynptr+1
    sty stmp             ; keep the screen column
    ldy #0
    +compose
    +compose
    +compose
    +compose
    +compose
    +compose
    +compose
    +compose
    ldy stmp
    lda dynnext
    clc
    adc #CH_DYN
    sta (scrlo),y
    lda scol
    sta (collo),y
    inc dynnext
sd_qnext:
    inc sq
    lda sq
    cmp #4
    beq sd_next
    jmp sd_quad
sd_next:
    inc sdi
    lda sdi
    cmp #8
    beq sd_done
    jmp sd_actor
sd_done:
    rts

sprbit: !byte 1, 2, 4, 8, 16, 32, 64, 128
qdx:    !byte 0, 1, 0, 1     ; the four cells: top-left, top-right,
qdy:    !byte 0, 0, 1, 1     ; bottom-left, bottom-right
qsrc_lo: !byte <blkl, <blkr, <(blkl+8), <(blkr+8)
qsrc_hi: !byte >blkl, >blkr, >(blkl+8), >(blkr+8)
zero8:  !fill 8, 0

!if (CH_DYN*8) & $ff != 0 { !error "the dynamic chars must start on a page" }

; ============================================================
; fade to black - eight passes walk every color RAM cell one
; luminance step down (luminance 0 goes black), half a screen
; per frame; then control jumps to the init routine the
; +fadeto macro left in fadevec
; ============================================================
fade_start:
    lda #$ff
    sta statbg           ; no status band while fading
    lda #0
    sta bflash
    sta borbase
    sta fadecnt
    sta fadehalf
    +setupd fade_update
    rts

!macro fadecell .addr {
    lda .addr,x
    and #$7f
    cmp #$10
    bcc .black
    sbc #$10             ; one luminance step darker
    bcs .store
.black:
    lda #0               ; luminance 0: black
.store:
    sta .addr,x
}

fade_update:
    lda fadehalf         ; half the color RAM per frame
    eor #1
    sta fadehalf
    bne fu_hi
    ldx #0
fu_lo:
    +fadecell COLRAM
    +fadecell COLRAM+$100
    inx
    bne fu_lo
    rts
fu_hi:
    ldx #0
fu_hi2:
    +fadecell COLRAM+$200
    +fadecell COLRAM+$2e8
    inx
    bne fu_hi2
    inc fadecnt
    lda fadecnt
    cmp #8               ; luminance 7 is black after eight
    bne fu_stay
    lda #0
    sta spren
    jmp (fadevec)        ; its rts returns to the main loop
fu_stay:
    rts

; ---- the custom tiles ----
tile_gfx:                ; CH_WALL: sandstone blocks, dark mortar
    !byte %11111111
    !byte %11110111
    !byte %11110111
    !byte %00000000
    !byte %11111111
    !byte %01111111
    !byte %01111111
    !byte %00000000
                         ; CH_POST: a bolted plate
    !byte %11111111
    !byte %10000001
    !byte %10111101
    !byte %10100101
    !byte %10100101
    !byte %10111101
    !byte %10000001
    !byte %11111111

portal_gfx:              ; CH_EXIT frame 0: closed
    !byte %00000000
    !byte %00011000
    !byte %00111100
    !byte %01100110
    !byte %01100110
    !byte %00111100
    !byte %00011000
    !byte %00000000
                         ; frame 1: opening
    !byte %00011000
    !byte %00111100
    !byte %01100110
    !byte %11000011
    !byte %11000011
    !byte %01100110
    !byte %00111100
    !byte %00011000
                         ; frame 2: wide open, sparkling
    !byte %00111100
    !byte %01100110
    !byte %11011011
    !byte %10111101
    !byte %10111101
    !byte %11011011
    !byte %01100110
    !byte %00111100
                         ; frame 3: closing again
    !byte %00011000
    !byte %00111100
    !byte %01100110
    !byte %11000011
    !byte %11000011
    !byte %01100110
    !byte %00111100
    !byte %00011000

barmask:                 ; bar cell fills, 1-7 pixels
    !byte $80, $c0, $e0, $f0, $f8, $fc, $fe

; ---- the actor shapes: 8x8, indexed by SHP_* ----
shapes:
                         ; SHP_RUN: the runner, a bright-eyed ball...
    !byte %00111100
    !byte %01111110
    !byte %11011011
    !byte %11111111
    !byte %11111111
    !byte %11111111
    !byte %01111110
    !byte %00111100
                         ; ...that bobs as it goes
    !byte %00000000
    !byte %00111100
    !byte %01111110
    !byte %11011011
    !byte %11111111
    !byte %11111111
    !byte %01111110
    !byte %00111100
                         ; SHP_SHOT: the bullet
    !byte %00000000
    !byte %00000000
    !byte %00011000
    !byte %00111100
    !byte %00111100
    !byte %00011000
    !byte %00000000
    !byte %00000000
                         ; SHP_CUR: the corner cursor, four brackets
    !byte %11100111
    !byte %10000001
    !byte %10000001
    !byte %00000000
    !byte %00000000
    !byte %10000001
    !byte %10000001
    !byte %11100111
                         ; SHP_STING: the scorpion's venom, a drop
    !byte %00000000
    !byte %00011000
    !byte %00111100
    !byte %01111110
    !byte %00111100
    !byte %00011000
    !byte %00000000
    !byte %00000000
                         ; SHP_ENA: a scarab, legs out...
    !byte %00100100
    !byte %10111101
    !byte %01111110
    !byte %11011011
    !byte %11011011
    !byte %01111110
    !byte %10111101
    !byte %00100100
                         ; ...and tucked as it scuttles
    !byte %00100100
    !byte %00111100
    !byte %11111111
    !byte %01011010
    !byte %01011010
    !byte %11111111
    !byte %00111100
    !byte %00100100
                         ; SHP_ENB: a scorpion, claws up, the tail
    !byte %11000011      ; swinging right...
    !byte %01100110
    !byte %00111100
    !byte %01111110
    !byte %00111100
    !byte %00011000
    !byte %00001100
    !byte %00011110
                         ; ...and left
    !byte %11000011
    !byte %01100110
    !byte %00111100
    !byte %01111110
    !byte %00111100
    !byte %00011000
    !byte %00110000
    !byte %01111000

; ---- graphics layer variables ----
sprxl:    !fill 8, 0     ; actor pixel positions (x low/high, y)
sprxh:    !fill 8, 0
spry:     !fill 8, 0
sprcol:   !fill 8, 0     ; actor colors
sprshape: !fill 8, 0     ; actor shape indices (SHP_*)
sprmode:  !byte 0, 1, 0, 0, 0, 0, 0, 0   ; 1 = covers its cell (the cursor)
spren:    !byte 0        ; enabled actors, one bit each
tgc:      !byte 0        ; set_target input: grid column / row
tgr:      !byte 0
tgxl:     !byte 0        ; set_target output: pixel target
tgxh:     !byte 0
tgy:      !byte 0
gspd:     !byte 0        ; spr_glide: pixels per frame
dtmp:     !byte 0        ; scratch
statbg:   !byte $ff      ; status band color, $ff = no band
bflash:   !byte 0        ; border flash: frames left + color
bcolor:   !byte 0
borbase:  !byte 0        ; steady border color of the screen
fadevec:  !byte 0, 0     ; where fade_update jumps when done
fadecnt:  !byte 0        ; fade passes completed
fadehalf: !byte 0        ; which color RAM half is next
ncells:   !byte 0        ; cells stamped by spr_draw
dynnext:  !byte 0        ; next free dynamic char
sdi:      !byte 0        ; spr_draw: actor index
sq:       !byte 0        ;   cell quadrant 0-3
sox:      !byte 0        ;   pixel offset inside the cell
soy:      !byte 0
scx:      !byte 0        ;   the actor's top-left cell
scy:      !byte 0
scol:     !byte 0        ;   its color and mode
smode:    !byte 0
scnt:     !byte 0        ;   shift counter
stmp:     !byte 0        ;   scratch
bgcode:   !byte 0        ;   the char underneath and its inverse mask
bgmask:   !byte 0
blkl:     !fill 16, 0    ; the shifted shape at its row offset: the
blkr:     !fill 16, 0    ;   16-row block of the two columns
sv_lo:    !fill NDYN, 0  ; stamped cells: screen address, char, color
sv_hi:    !fill NDYN, 0
sv_ch:    !fill NDYN, 0
sv_col:   !fill NDYN, 0

!if (fadevec & 255) = 255 { !error "fadevec must not straddle a page" }
!if * > CHARSET { !error "the program ran into the charset at $5000" }

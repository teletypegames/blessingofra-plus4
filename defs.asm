; -----------------------------------------------------------
; defs.asm - hardware registers, constants, zero page, macros
; included first by main.asm
; -----------------------------------------------------------

; ---- TED registers ----
TED_CTL2  = $ff07        ; control 2: bit 7 = 256 chars (no inverse)
TED_KBD   = $ff08        ; keyboard/joystick latch (a write strobes it)
TED_IRQ   = $ff09        ; interrupt flags (write 1 to clear)
TED_IMASK = $ff0a        ; interrupt enable + raster compare bit 8
TED_RCMP  = $ff0b        ; raster compare, low 8 bits
TED_S2FL  = $ff0f        ; sound voice 2 frequency, low 8 bits
TED_S2FH  = $ff10        ; voice 2 frequency, bits 8-9
TED_SND   = $ff11        ; sound control: noise, voices, volume
TED_CHR   = $ff12        ; bit 2: char data from ROM (1) / RAM (0)
TED_CHRB  = $ff13        ; bits 7-2: charset base A15-A10
BG        = $ff15        ; background color register
BORDER    = $ff19        ; border color register
RASTER    = $ff1d        ; raster line, low 8 bits
TED_T1LO  = $ff00        ; timer 1 low byte: free-running entropy
RAM_IN    = $ff3f        ; a write banks RAM in over the ROMs
KBD_COLS  = $fd30        ; keyboard column select (0 = selected)
IRQVEC    = $fffe        ; the CPU's IRQ vector (RAM once banked)

SCREEN  = $0c00          ; screen RAM (40x25 chars)
COLRAM  = $0800          ; color RAM: luminance << 4 | hue
COLOFF  = $fc              ; screen high byte + this = color RAM
!if ((SCREEN >> 8) + COLOFF) & $ff != (COLRAM >> 8) { !error "COLOFF does not reach the color RAM" }
CHARSET = $5000          ; RAM charset: 128 ROM chars + the tiles
CHARROM = $d000          ; the uppercase set inside the KERNAL ROM

; ---- SFX IDs ----
SFX_CURSOR = 0           ; corner cursor step: click
SFX_SELECT = 1           ; menu fire: rising tone
SFX_ROTATE = 2           ; wall spin: noise whoosh
SFX_DENY   = 3           ; blocked spin: low buzz
SFX_WIN    = 4           ; escape: rising jingle
SFX_LOSE   = 5           ; caught: descending sweep
SFX_SHOT   = 6           ; gun / scorpion sting: short high tick
SFX_HIT    = 7           ; enemy hit: noise burst
NSFX       = 8

; ---- colors: luminance in the high nibble, hue in the low ----
BLACK   = $00
WHITE   = $71
RED     = $32
CYAN    = $53
PURPLE  = $44
GREEN   = $45
BLUE    = $26
YELLOW  = $67
ORANGE  = $48
BROWN   = $29
LRED    = $52
DGREY   = $21
MGREY   = $41
LGREEN  = $65
LBLUE   = $5d
LGREY   = $51

; ---- joystick bits (after read_joy / read_joy2, active high) ----
JOY_UP    = 1
JOY_DOWN  = 2
JOY_LEFT  = 4
JOY_RIGHT = 8
JOY_FIRE  = 16

; ---- the maze ----
; a lattice of (2*cells+1) chars per side, centered on rows
; 1-23; local coordinates inside the lattice:
;   cell  = odd column,  odd row   (walkable)
;   post  = even column, even row  (pivot, always solid)
;   slot  = the rest: wall pieces that spin around the posts
; wall thickness therefore equals corridor width: one cell
; the levels are squares, one cell bigger each level: MZMIN
; up to MZMAX (11x11 cells = 23x23 chars, the tallest square
; the screen fits); the menu backdrop uses the full lattice
MZMIN    = 4             ; level 1: 4x4 cells
MZMAX    = 11            ; level 8: 11x11 cells
MAZE_CW  = 19            ; the largest lattice: the menu backdrop
MAZE_CH  = 11
NCELLS   = MAZE_CW * MAZE_CH
NENEMIES = 4             ; enemy actor slots (a level uses 1-4)

; ---- characters (the custom tiles live in the RAM charset,
; on graphic codes no text ever uses; codes $80-$ff are the
; TED's hardware inverses, $a0 = solid block) ----
CH_WALL   = $41          ; sandstone block: spinnable wall piece
CH_POST   = $42          ; bolted plate: fixed pivot post
CH_EXIT   = $43          ; the portal out (4 animated glyph frames)
CH_FLOOR  = $20          ; space: corridor
CH_BAR    = $44          ; 7 chars: a bar cell 1-7 pixels full
CH_RELIC  = $31          ; the relics wear their order: '1'-'9'
NRELIC    = 9            ; most relics on a level (level 8)
CH_DYN    = $60          ; 32 dynamic chars: the actors, composed
NDYN      = 32           ;   over the maze every frame

; ---- the actors are software sprites (see gfx.asm) ----
SP_RUN   = 0             ; player 1, the worker
SP_CUR   = 1             ; player 2, ra's cursor
SP_SHOT  = 2             ; the optional bullet
SP_EN    = 3             ; the enemies ride slots 3-6
SP_STING = 7             ; the scorpions' venom sting

; ---- shape indices into the 8x8 shape table ----
SHP_RUN   = 0            ; two frames: the worker bobs
SHP_SHOT  = 2
SHP_CUR   = 3
SHP_STING = 4
SHP_ENA   = 5            ; two frames: the scarab scuttles
SHP_ENB   = 7            ; two frames: the scorpion's tail swings

; ---- desert palette ----
COL_WALL = ORANGE        ; sandstone wall pieces
COL_POST = BROWN         ; fixed pivot posts
COL_EXIT = LGREEN        ; the exit portal
COL_HILITE = YELLOW      ; walls the cursor's spin would move
COL_SCARAB = CYAN        ; the scarabs
COL_SCORP  = LRED        ; the scorpions
COL_STING  = PURPLE      ; the venom sting
COL_RELIC  = LBLUE       ; the numbered relics (relic order option)
STATCOL  = BROWN         ; background band behind the status row

; ---- game timing ----
REP_HOLD    = 10         ; runner: frames before a held dir repeats
REP_PERIOD  = 5          ; runner: frames between repeat steps
CREP_HOLD   = 12         ; cursor: same, a touch slower
CREP_PERIOD = 7
COOL_TIME   = 160        ; spin cooldown option: recharge frames
RESPAWN_TIME = 150       ; gun option: frames until a hit enemy returns
BUILD_STEPS = 8          ; maze carve animation: generator steps a frame

; ---- raster geometry (PAL: 312 lines, the 25 text rows start
; on line WIN_TOP) ----
WIN_TOP   = 4            ; first raster line of text row 0
RAS_SYNC  = WIN_TOP + 192    ; frame sync: the last text row (no actors there)
BAND_LINE = WIN_TOP - 2  ; status band on: in the top border
BAND_END  = WIN_TOP + 8  ; status band off: row 1's first line
BAND_ARM  = BAND_END - 1 ; the IRQ that waits for BAND_END

; ---- zero page pointers ----
shl    = $ed             ; software sprites: shift table pages (2 bytes each)
shr    = $ef
dynptr = $f1             ; software sprites: dynamic char being built
shptr  = $f3             ; software sprites: the actor's shape
txtlo  = $f5             ; text pointer for the print routines (2 bytes)
txthi  = $f6
bgptr  = $f7             ; software sprites: background glyph (2 bytes)
updvec = $f9             ; state update vector (2 bytes)
scrlo  = $fb
scrhi  = $fc
collo  = $fd
colhi  = $fe

; ---- helper macros: print a normal / big text line ----
!macro prtext .row, .col, .color, .txt, .len {
    lda #<.txt
    sta txtlo
    lda #>.txt
    sta txthi
    lda #.row
    sta prow
    lda #.col
    sta pcol
    lda #.color
    sta pcolor
    lda #.len
    sta plen
    jsr print_text
}

!macro prbig .row, .col, .color, .txt, .len {
    lda #<.txt
    sta txtlo
    lda #>.txt
    sta txthi
    lda #.row
    sta bigrow
    lda #.col
    sta bigcol
    lda #.color
    sta bigcolor
    lda #.len
    sta biglen
    jsr draw_big
}

; ---- set the state update vector ----
!macro setupd .addr {
    lda #<.addr
    sta updvec
    lda #>.addr
    sta updvec+1
}

; ---- leave the current screen: fade to black, then run the
; init routine of the next one ----
!macro fadeto .addr {
    lda #<.addr
    sta fadevec
    lda #>.addr
    sta fadevec+1
    jmp fade_start
}

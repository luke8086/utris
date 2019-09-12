;
; Rudimentary self-hosting tetris clone that fits into a 512b bootsector
;
; Installation:
;   $ nasm tetris.asm -o tetris.o
;   $ dd if=tetris.o of=/dev/fd0 conv=notrunc
;
; Controls:
;   move   - left/right/down
;   rotate - up
;   drop   - space bar
;
; Copyright (c) 2012  Lukasz S.
; Distributed under the terms of GPL-2 License.
;

[bits 16]
[org 0x7c00]

; 80x25 screen
SCREEN_W    equ 0x50
SCREEN_H    equ 0x19

; 10x20 board
BOARD_X     equ 0x18
BOARD_Y     equ 0x02
BOARD_W     equ 0x0a
BOARD_H     equ 0x13

; next-piece box
PANEL_X     equ BOARD_X + BOARD_W * 2 + 0x06
PANEL_Y     equ BOARD_Y
PANEL_W     equ 0x06
PANEL_H     equ 0x08

; piece's default position
PIECE_X     equ 0x03 + BOARD_X / 2
PIECE_Y     equ 0x00 + BOARD_Y

; piece structure: 4 rotations + 1 color
PIECE_SIZE  equ 0x09
PIECE_COUNT equ 0x07

; data offsets relative to si
DATA_COL    equ 0x00
DATA_TIME   equ 0x01
DATA_NEXT   equ 0x03

; game
GAME_SPEED  equ 0x0e

; ---------------------------------------------------------------------
; Starting point

main:
    ; so we can simply use [si] and save few bytes
    push cs
    pop ds

    ; video ram
    push 0xb800
    pop es

    ; conventional ram, right after our code
    mov si, 0x0200
    mov byte [si+DATA_NEXT], 0x00

    ; disable blinking, enable bright bg colors
    mov ax, 0x1003
    xor bx, bx
    int 0x10

    ; hide cursor
    mov ah, 0x02
    mov dh, SCREEN_H
    int 0x10

    ; draw blue border
    mov ax, 0x1700
    mov cx, SCREEN_W * SCREEN_H
    xor di, di
    rep stosw

    ; draw gray background
    mov ah, 0x70
    mov cx, SCREEN_W * (SCREEN_H - 2)
    mov di, SCREEN_W * 2
    rep stosw

    ; draw board
    mov ax, 0x0600
    mov cx, (BOARD_Y << 8) | (BOARD_X)
    mov dx, ((BOARD_Y + BOARD_H - 1) << 8) | (BOARD_X + BOARD_W * 2 - 1)
    int 0x10

    jmp .next_piece

.game_loop:

; ---------------------------------------------------------------------
; Handle keyboard

    ; check for pressed key
    mov ah, 0x01
    int 0x16
    jz .skip_keyboard

    ; read scancode to ah
    xor ah, ah
    int 0x16
    mov cl, ah

    ; right
    cmp cl, 0x4d
    sete al

    ; left
    cmp cl, 0x4b
    jne .skip_left
    dec al
.skip_left:

    ; up (rotate)
    cmp cl, 0x48
    sete ch

    ; down
    cmp cl, 0x50
    sete ah

    ; space bar
    cmp cl, 0x39
    jne .skip_space
    mov ah, BOARD_H
.skip_space:

    call move_piece

.skip_keyboard:

; ---------------------------------------------------------------------
; Handle timer

    ; call rtc
    xor ah, ah
    int 0x1a

    ; wait
    mov ax, dx
    xor bh, bh
    sub ax, GAME_SPEED
    sub ax, [si+DATA_TIME]
    jb .game_loop
    mov [si+DATA_TIME], dx

    ; move down and check if we hit the ground
    mov ax, 0x0100
    xor ch, ch
    call move_piece
    cmp byte [si+DATA_COL], 0x00
    je .game_loop

; ---------------------------------------------------------------------
; Remove full rows

    mov dh, BOARD_Y + BOARD_H - 1
.check_rows_loop:
    mov dl, BOARD_X
    mov ah, 0xff
    mov cx, BOARD_W

    .check_row_loop:
        ; assume ch == 0
        mov byte [si+DATA_COL], ch
        call run_block
        cmp byte [si+DATA_COL], ch
        je .skip_row

        add dl, 0x02
        loop .check_row_loop

    ; remove whole row
    mov ax, 0x0701
    xor bh, bh
    mov cx, (BOARD_Y << 8) | (BOARD_X)
    dec dl
    int 0x10
    jmp short .check_rows_loop

.skip_row:
    dec dh
    cmp dh, BOARD_Y + 1
    ja .check_rows_loop


; ---------------------------------------------------------------------
; Generate new piece

.next_piece:
    ; use rtc to find random number
    rdtsc
    xor ah, ah
    mov bl, PIECE_COUNT
    div bl

    ; save as next-piece and restore previous one
    mov al, ah
    xchg ah, [si+DATA_NEXT]

    ; clear next-piece box
    pusha
    mov ax, 0x0600
    xor bx, bx
    mov cx, PANEL_Y << 8 | PANEL_X
    mov dx, (PANEL_Y + PANEL_H - 1) << 8 | (PANEL_X + PANEL_W * 2 + 1)

    ; preserve ax
    pusha
    int 0x10
    popa

    ; clear shadow box
    mov cx, ((BOARD_Y + BOARD_H + 1) << 8) | (BOARD_X)
    mov dx, ((BOARD_Y + BOARD_H + 1) << 8) | (BOARD_X + BOARD_W * 2 - 1)
    int 0x10
    popa

    ; draw in next-piece box
    xor cl, cl
    mov dx, (PANEL_Y - BOARD_Y + 4) << 8 | PANEL_X - BOARD_X + 1
    mov bl, 0x01
    call run_piece

    ; store rotation:piece at once (ah == 0 == rotation)
    shr ax, 0x08
    mov gs, ax

    ; default position
    mov dx, PIECE_Y << 8 | PIECE_X
    mov fs, dx

    ; draw new piece (assume cl == 0)
    mov byte [si+DATA_COL], cl
    call run_piece

    ; if there is no place, restart whole game
    cmp byte [si+DATA_COL], cl
    jne main

    jmp .game_loop

; ---------------------------------------------------------------------
; Draw / collision-check a block
; Args:
;   ax - character
;   dl, dh - x, y

run_block:
    pusha

    ; calculate position
    xor bx, bx
    mov bl, dh
    imul bx, SCREEN_W
    xor dh, dh
    add bx, dx
    shl bx, 0x01
    mov di, bx

    ; check for collision
    mov bx, word [es:di]
    or byte [si+DATA_COL], bh

    ; if collision-check mode
    cmp ah, 0xff
    je .skip_print

    stosw
    stosw

.skip_print:

    popa
    ret

; ---------------------------------------------------------------------
; Draw / clear / collision-check a piece
; Args:
;   al - piece index
;   bl - mode (0 - clear, 1 - draw, 0xff - collision check),
;   cl - rotation
;   dh, dl - x, y

run_piece:
    pusha

    ; find piece
    mov di, pieces
    xor ah, ah
    imul ax, PIECE_SIZE
    add di, ax

    ; load color for drawing mode
    cmp bl, 0x01
    jne .skip_color
    mov bl, byte [di+0x08]


.skip_color:

    ; load shape of specified rotation
    xor ch, ch
    shl cx, 0x01
    add di, cx
    mov ax, [di]

    ; loop the shape bit after bit
    mov cx, 0x8000

.run_piece_loop:
    test ax, cx
    jz .skip_draw

    pusha

    ; each block consists of two empty characters
    shl dl, 0x01
    xor ax, ax
    mov ah, bl
    call run_block

    ; draw shadow
    cmp dl, BOARD_X + BOARD_W * 2
    jge .skip_shadow
    push dx
    mov dh, BOARD_Y + BOARD_H + 1
    push word [si+DATA_COL]
    call run_block
    pop word [si+DATA_COL]
    pop dx
.skip_shadow:

    jmp short .draw_done

.collision:
    mov byte [si+DATA_COL], 0x01

.draw_done:
    popa

.skip_draw:
    shr cx, 0x01
    inc dl

    ; after 4 blocks move to the next row
    test cx, 0x0888
    jz .skip_next_row
    sub dl, 0x04
    inc dh
.skip_next_row:

    test cx, cx
    jnz  .run_piece_loop

    popa
    ret

; ---------------------------------------------------------------------
; Moves current piece
; Args:
;   ah, al - dx, dy
;   ch - rotation
; Note: clutters regs

move_piece:
    ; erase current
    push ax
    mov ax, gs
    mov cl, ah
    mov dx, fs
    xor bl, bl
    call run_piece
    pop ax

    ; move sideways and rotate
    add dl, al
    add cl, ch
    and cl, 0x03
    mov ch, ah

.down_loop:
    ; check for collision
    mov ax, gs
    mov bl, 0xff
    mov byte [si+DATA_COL], 0x00
    call run_piece
    cmp byte [si+DATA_COL], 0x00
    jne .collision

    ; save new position
    mov ah, cl
    mov gs, ax
    mov fs, dx

    ; step down one by one until we're done or we find a collision
    dec ch
    js .break_down_loop
    inc dh
    jmp short .down_loop
.break_down_loop:

    ; finally draw
    mov bl, 0x01
    call run_piece

    ret

.collision:
    ; restore previous position
    mov ax, gs
    mov cl, ah
    mov dx, fs
    mov bl, 0x01
    call run_piece

    ret

; ---------------------------------------------------------------------
; original rotation and colors
; source: http://tetris.wikia.com/wiki/Tetris_(IBM_PC)

pieces:
    dw 0x4444, 0x0f00, 0x4444, 0x0f00 ; I
    db 0x40 ; red
    dw 0x44c0, 0x8e00, 0x6440, 0x0e20 ; J
    db 0xf0 ; white
    dw 0x4460, 0x0e80, 0xc440, 0x2e00 ; L
    db 0x50 ; magenta
    dw 0x0cc0, 0x0cc0, 0x0cc0, 0x0cc0 ; O
    db 0x10 ; blue
    dw 0x06c0, 0x4620, 0x06c0, 0x4620 ; S
    db 0x20 ; green
    dw 0x4e00, 0x4640, 0x0e40, 0x4c40 ; T
    db 0x60 ; brown
    dw 0x0c60, 0x2640, 0x0c60, 0x2640 ; Z
    db 0x30 ; cyan

; ---------------------------------------------------------------------
times 510-($-$$) db 0
dw 0xAA55

; vim: ft=nasm

; ====================================================================
; 8051 貪食蛇專案 - 階段三：食物生成與吃食長大 (最終完整可玩版)
; 晶振頻率：12MHz / 適用於標準 Intel 8051 編譯器
; ====================================================================

        ORG     0000H
        LJMP    MAIN
        
        ORG     000BH               ; Timer 0 中斷進入點
        LJMP    T0_ISR

; --------------------------------------------------------------------
; 常數與暫存器位置定義
; --------------------------------------------------------------------
RS          EQU     P1.6
EN          EQU     P1.7
DATA_PORT   EQU     P0

; RAM 位置分配
SNAKE_LEN   EQU     40H             ; 蛇目前長度
SNAKE_DIR   EQU     41H             ; 方向 (0:上, 1:下, 2:左, 3:右)
MOVE_FLAG   EQU     42H             ; 移動驅動旗標
T0_COUNT    EQU     43H             ; 中斷計數器
TAIL_X      EQU     44H             ; 舊蛇尾暫存 X
TAIL_Y      EQU     45H             ; 舊蛇尾暫存 Y
NEXT_X      EQU     46H             ; 下一格預期蛇頭 X
NEXT_Y      EQU     47H             ; 下一格預期蛇頭 Y
FOOD_X      EQU     48H             ; 食物 X 座標
FOOD_Y      EQU     49H             ; 食物 Y 座標
EAT_FLAG    EQU     4AH             ; 是否吃到食物旗標 (0:沒吃, 1:吃了)
SEED_X      EQU     4BH             ; 隨機數種子 X
SEED_Y      EQU     4CH             ; 隨機數種子 Y

SNAKE_X     EQU     50H             ; 蛇身 X 陣列起點 (50H=頭)
SNAKE_Y     EQU     60H             ; 蛇身 Y 陣列起點 (60H=頭)

; --------------------------------------------------------------------
; 主程式初始化
; --------------------------------------------------------------------
MAIN:
        MOV     SP, #70H            ; 堆疊移至安全高位
        ACALL   DELAY_50MS
        ACALL   LCD_INIT

        ; --- 初始化遊戲數據 ---
        MOV     SNAKE_LEN, #3       ; 初始長度為 3
        MOV     SNAKE_DIR, #3       ; 初始方向向右 (3)
        MOV     MOVE_FLAG, #0
        MOV     T0_COUNT, #0
        MOV     EAT_FLAG, #0
        MOV     SEED_X, #13
        MOV     SEED_Y, #7

        ; 設定初始蛇身坐標 (頭在 (3,0)，身體在 (2,0), (1,0))
        MOV     SNAKE_X, #3
        MOV     SNAKE_Y, #0
        MOV     51H, #2
        MOV     61H, #0
        MOV     52H, #1
        MOV     62H, #0

        ; 畫出初始整條蛇
        ACALL   DRAW_FULL_SNAKE

        ; 初始化第一個食物的位置在 (9, 1) 並顯示
        MOV     FOOD_X, #9
        MOV     FOOD_Y, #1
        MOV     R0, FOOD_X
        MOV     R1, FOOD_Y
        ACALL   GOTO_XY
        MOV     A, #'$'             ; 食物用 '$' 符號表示
        ACALL   LCD_DATA

        ; --- 初始化 Timer 0 (50ms 中斷一次) ---
        MOV     TMOD, #01H
        MOV     TH0, #3CH
        MOV     TL0, #0B0H
        SETB    ET0
        SETB    EA
        SETB    TR0

; --------------------------------------------------------------------
; 遊戲主迴圈
; --------------------------------------------------------------------
GAME_LOOP:
        ; 不斷高速累加隨機數種子，創造無法預測的隨機性
        INC     SEED_X
        MOV     A, SEED_Y
        ADD     A, #3
        MOV     SEED_Y, A

        ; 1. 檢查鍵盤輸入
        ACALL   KEY_SCAN
        
        CJNE    A, #2, NOT_KEY_UP
        MOV     A, SNAKE_DIR
        CJNE    A, #1, SET_UP
        SJMP    NOT_KEY_UP
SET_UP:
        MOV     SNAKE_DIR, #0
        SJMP    KEY_DONE

NOT_KEY_UP:
        CJNE    A, #8, NOT_KEY_DOWN
        MOV     A, SNAKE_DIR
        CJNE    A, #0, SET_DOWN
        SJMP    NOT_KEY_DOWN
SET_DOWN:
        MOV     SNAKE_DIR, #1
        SJMP    KEY_DONE

NOT_KEY_DOWN:
        CJNE    A, #4, NOT_KEY_LEFT
        MOV     A, SNAKE_DIR
        CJNE    A, #3, SET_LEFT
        SJMP    NOT_KEY_LEFT
SET_LEFT:
        MOV     SNAKE_DIR, #2
        SJMP    KEY_DONE

NOT_KEY_LEFT:
        CJNE    A, #6, KEY_DONE
        MOV     A, SNAKE_DIR
        CJNE    A, #2, SET_RIGHT
        SJMP    KEY_DONE
SET_RIGHT:
        MOV     SNAKE_DIR, #3

KEY_DONE:
        ; 2. 檢查定時移動旗標 (500ms 時間到)
        MOV     A, MOVE_FLAG
        JZ      GAME_LOOP
        
        MOV     MOVE_FLAG, #0
        ACALL   UPDATE_SNAKE        ; 更新位置與吃食判定
        ACALL   REFRESH_SCREEN      ; 刷新螢幕顯示
        
        SJMP    GAME_LOOP

; --------------------------------------------------------------------
; Timer 0 中斷服務常式 (ISR) - 每 50ms 觸發一次
; --------------------------------------------------------------------
T0_ISR:
        MOV     TH0, #3CH
        MOV     TL0, #0B0H
        INC     T0_COUNT
        MOV     A, T0_COUNT
        CJNE    A, #10, T0_EXIT
        
        MOV     T0_COUNT, #0
        MOV     MOVE_FLAG, #1
T0_EXIT:
        RETI

; --------------------------------------------------------------------
; 子程式：更新蛇的位置邏輯與吃食判定
; --------------------------------------------------------------------
UPDATE_SNAKE:
        ; A. 先依據方向計算出下一格蛇頭預期的全新位置 (NEXT_X, NEXT_Y)
        MOV     A, SNAKE_DIR
        CJNE    A, #0, U_CHK_DN
        ; 向上移動
        MOV     A, SNAKE_Y
        DEC     A
        ANL     A, #01H
        MOV     NEXT_Y, A
        MOV     NEXT_X, SNAKE_X
        SJMP    U_CHK_FOOD
U_CHK_DN:
        CJNE    A, #1, U_CHK_LF
        ; 向下移動
        MOV     A, SNAKE_Y
        INC     A
        ANL     A, #01H
        MOV     NEXT_Y, A
        MOV     NEXT_X, SNAKE_X
        SJMP    U_CHK_FOOD
U_CHK_LF:
        CJNE    A, #2, U_CHK_RT
        ; 向左移動
        MOV     A, SNAKE_X
        DEC     A
        ANL     A, #0FH
        MOV     NEXT_X, A
        MOV     NEXT_Y, SNAKE_Y
        SJMP    U_CHK_FOOD
U_CHK_RT:
        ; 向右移動
        MOV     A, SNAKE_X
        INC     A
        ANL     A, #0FH
        MOV     NEXT_X, A
        MOV     NEXT_Y, SNAKE_Y

U_CHK_FOOD:
        ; B. 核心吃食檢查：預期新頭是否撞到食物？
        MOV     A, NEXT_X
        CJNE    A, FOOD_X, NOT_EATEN
        MOV     A, NEXT_Y
        CJNE    A, FOOD_Y, NOT_EATEN
        
        ; --- 吃到食物狀況 ---
        MOV     EAT_FLAG, #1        ; 設定吃到旗標
        INC     SNAKE_LEN           ; 蛇長度直接增加 1
        ACALL   GENERATE_FOOD       ; 生成下一個新食物
        SJMP    DO_SHIFT            ; 長度增加後直接去搬移身體（原尾巴會被自動保留）

NOT_EATEN:
        ; --- 沒吃到食物狀況 ---
        MOV     EAT_FLAG, #0
        ; 必須備份舊尾巴座標，等一下刷新螢幕時要把牠擦除
        MOV     A, SNAKE_LEN
        DEC     A
        MOV     R0, A               ; R0 = 長度 - 1
        
        MOV     A, #SNAKE_X
        ADD     A, R0
        MOV     R1, A
        MOV     TAIL_X, @R1         ; 暫存尾巴 X
        
        MOV     A, #SNAKE_Y
        ADD     A, R0
        MOV     R1, A
        MOV     TAIL_Y, @R1         ; 暫存尾巴 Y

DO_SHIFT:
        ; C. 身體節點前移 (後一格複製前一格)
        MOV     A, SNAKE_LEN
        DEC     A
        MOV     R0, A               ; R0 起始點為最尾巴的索引
        
U_SHIFT_BODY:
        MOV     A, R0
        JZ      U_SHIFT_DONE        ; 移動到蛇頭 (0) 則結束
        
        ; X 陣列搬移
        DEC     R0
        MOV     A, #SNAKE_X
        ADD     A, R0
        MOV     R1, A
        MOV     A, @R1
        INC     R0
        PUSH    ACC
        MOV     A, #SNAKE_X
        ADD     A, R0
        MOV     R1, A
        POP     ACC
        MOV     @R1, A
        
        ; Y 陣列搬移
        DEC     R0
        MOV     A, #SNAKE_Y
        ADD     A, R0
        MOV     R1, A
        MOV     A, @R1
        INC     R0
        PUSH    ACC
        MOV     A, #SNAKE_Y
        ADD     A, R0
        MOV     R1, A
        POP     ACC
        MOV     @R1, A
        
        DEC     R0
        SJMP    U_SHIFT_BODY

U_SHIFT_DONE:
        ; D. 將計算好的全新頭部寫入陣列第 0 格
        MOV     SNAKE_X, NEXT_X
        MOV     SNAKE_Y, NEXT_Y
        RET

; --------------------------------------------------------------------
; 子程式：產生全新隨機食物
; --------------------------------------------------------------------
GENERATE_FOOD:
        ; 抓取當下的隨機種子
        MOV     A, SEED_X
        ANL     A, #0FH             ; 強制限制在 0~15 (LCD行寬)
        MOV     FOOD_X, A
        
        MOV     A, SEED_Y
        ANL     A, #01H             ; 強制限制在 0~1 (LCD列高)
        MOV     FOOD_Y, A
        
        ; 在畫面上繪製出這個新食物
        MOV     R0, FOOD_X
        MOV     R1, FOOD_Y
        ACALL   GOTO_XY
        MOV     A, #'$'
        ACALL   LCD_DATA
        RET

; --------------------------------------------------------------------
; 子程式：局部螢幕刷新
; --------------------------------------------------------------------
REFRESH_SCREEN:
        ; 檢查剛剛有沒有吃到食物
        MOV     A, EAT_FLAG
        JNZ     DRAW_HEAD           ; 如果吃了食物，跳過擦除步驟，尾巴留著（蛇變長）
        
        ; 沒吃到食物：擦除舊尾巴
        MOV     R0, TAIL_X
        MOV     R1, TAIL_Y
        ACALL   GOTO_XY
        MOV     A, #' '
        ACALL   LCD_DATA

DRAW_HEAD:
        ; 無論如何，都要畫上全新的蛇頭
        MOV     R0, SNAKE_X
        MOV     R1, SNAKE_Y
        ACALL   GOTO_XY
        MOV     A, #'*'
        ACALL   LCD_DATA
        RET

; --------------------------------------------------------------------
; 子程式：繪製整條初始蛇
; --------------------------------------------------------------------
DRAW_FULL_SNAKE:
        MOV     R3, #0
DRAW_LOOP:
        MOV     A, #SNAKE_X
        ADD     A, R3
        MOV     R0, A
        MOV     A, @R0
        MOV     R4, A
        
        MOV     A, #SNAKE_Y
        ADD     A, R3
        MOV     R0, A
        MOV     A, @R0
        MOV     R1, A
        MOV     R0, R4
        
        ACALL   GOTO_XY
        MOV     A, #'*'
        ACALL   LCD_DATA
        
        INC     R3
        MOV     A, R3
        CJNE    A, SNAKE_LEN, DRAW_LOOP
        RET

; --------------------------------------------------------------------
; 子程式：移動游標至指定的 (X, Y) 坐標
; --------------------------------------------------------------------
GOTO_XY:
        MOV     A, R1
        JZ      ROW_0
        MOV     A, #0C0H
        ADD     A, R0
        ACALL   LCD_CMD
        RET
ROW_0:
        MOV     A, #80H
        ADD     A, R0
        ACALL   LCD_CMD
        RET

; --------------------------------------------------------------------
; 子程式：4x4 鍵盤掃描 (完全展開版)
; --------------------------------------------------------------------
KEY_SCAN:
        CLR     P1.0
        SETB    P1.1
        SETB    P1.2
        SETB    P1.3
        MOV     A, P2
        ANL     A, #0FH
        CJNE    A, #0FH, R0_HIT

        SETB    P1.0
        CLR     P1.1
        SETB    P1.2
        SETB    P1.3
        MOV     A, P2
        ANL     A, #0FH
        CJNE    A, #0FH, R1_HIT

        SETB    P1.0
        SETB    P1.1
        CLR     P1.2
        SETB    P1.3
        MOV     A, P2
        ANL     A, #0FH
        CJNE    A, #0FH, R2_HIT

        SETB    P1.0
        SETB    P1.1
        SETB    P1.2
        CLR     P1.3
        MOV     A, P2
        ANL     A, #0FH
        CJNE    A, #0FH, R3_HIT

        MOV     A, #0FFH
        RET

R0_HIT:
        MOV     R2, #0
        SJMP    DECODE_COL
R1_HIT:
        MOV     R2, #4
        SJMP    DECODE_COL
R2_HIT:
        MOV     R2, #8
        SJMP    DECODE_COL
R3_HIT:
        MOV     R2, #12
        SJMP    DECODE_COL

DECODE_COL:
        JB      ACC.0, NOT_C0
        MOV     A, #0
        ADD     A, R2
        RET
NOT_C0:
        JB      ACC.1, NOT_C1
        MOV     A, #1
        ADD     A, R2
        RET
NOT_C1:
        JB      ACC.2, NOT_C2
        MOV     A, #2
        ADD     A, R2
        RET
NOT_C2:
        JB      ACC.3, KEY_ERR
        MOV     A, #3
        ADD     A, R2
        RET
KEY_ERR:
        MOV     A, #0FFH
        RET

; --------------------------------------------------------------------
; 子程式：LCD 驅動與延時基礎常式 (完全展開版)
; --------------------------------------------------------------------
LCD_INIT:
        MOV     A, #38H
        ACALL   LCD_CMD
        MOV     A, #0CH
        ACALL   LCD_CMD
        MOV     A, #06H
        ACALL   LCD_CMD
        MOV     A, #01H
        ACALL   LCD_CMD
        RET

LCD_CMD:
        MOV     DATA_PORT, A
        CLR     RS
        SETB    EN
        ACALL   DELAY_1MS
        CLR     EN
        ACALL   DELAY_5MS
        RET

LCD_DATA:
        MOV     DATA_PORT, A
        SETB    RS
        SETB    EN
        ACALL   DELAY_1MS
        CLR     EN
        ACALL   DELAY_5MS
        RET

DELAY_1MS:
        MOV     R7, #2
D1:     MOV     R6, #250
        DJNZ    R6, $
        DJNZ    R7, D1
        RET

DELAY_5MS:
        MOV     R7, #10
D5:     MOV     R6, #250
        DJNZ    R6, $
        DJNZ    R7, D5
        RET

DELAY_50MS:
        MOV     R4, #250
D50_1:  MOV     R3, #100
        DJNZ    R3, $
        DJNZ    R4, D50_1
        RET

        END
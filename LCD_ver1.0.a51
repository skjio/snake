; ====================================================================
; 8051 貪食蛇專案 - 最終完美修正版 (解決中斷暫存器衝突、蛇亂動 Bug)
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
BUZZER      EQU     P2.6            ; 蜂鳴器接在 P2.6

; RAM 位置分配
SNAKE_LEN   EQU     40H             ; 蛇目前長度
SNAKE_DIR   EQU     41H             ; 方向 (0:上, 1:下, 2:左, 3:右)
MOVE_FLAG   EQU     42H             ; 移動驅動旗?
T0_COUNT    EQU     43H             ; 中斷計數器
TAIL_X      EQU     44H             ; 舊蛇尾暫存 X
TAIL_Y      EQU     45H             ; 舊蛇尾暫存 Y
NEXT_X      EQU     46H             ; 下一格預期蛇頭 X
NEXT_Y      EQU     47H             ; 下一格預期蛇頭 Y
FOOD_X      EQU     48H             ; 食物 X 座標
FOOD_Y      EQU     49H             ; 食物 Y 座標
EAT_FLAG    EQU     4AH             ; 是否吃到食物旗標
SEED_X      EQU     4BH             ; 隨機數種子 X
SEED_Y      EQU     4CH             ; 隨機數種子 Y

SNAKE_X     EQU     50H             ; 蛇身 X 陣列起點 (50H=頭)
SNAKE_Y     EQU     60H             ; 蛇身 Y 陣列起點 (60H=頭)

; --------------------------------------------------------------------
; 主程式初始化
; --------------------------------------------------------------------
MAIN:
        MOV     SP, #70H            ; 堆疊移至安全高位
        SETB    BUZZER              ; 讓蜂鳴器一開始保持安靜
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

        ; 設定初始蛇身坐標
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
        MOV     A, #'$'
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
        INC     SEED_X              ; 瘋狂累加隨機種子
        MOV     A, SEED_Y
        ADD     A, #3
        MOV     SEED_Y, A

        ; 1. 檢查鍵盤輸入
        ACALL   KEY_SCAN
        
        ; --- 檢查「上」方向鍵 (解碼值 1) ---
        CJNE    A, #1, NOT_KEY_UP
        MOV     A, SNAKE_DIR
        CJNE    A, #1, SET_UP       
        SJMP    NOT_KEY_UP
SET_UP:
        MOV     SNAKE_DIR, #0
        SJMP    KEY_DONE

NOT_KEY_UP:
        ; --- 檢查「下」方向鍵 (解碼值 9) ---
        CJNE    A, #9, NOT_KEY_DOWN
        MOV     A, SNAKE_DIR
        CJNE    A, #0, SET_DOWN     
        SJMP    NOT_KEY_DOWN
SET_DOWN:
        MOV     SNAKE_DIR, #1
        SJMP    KEY_DONE

NOT_KEY_DOWN:
        ; --- 檢查「左」方向鍵 (解碼值 4) ---
        CJNE    A, #4, NOT_KEY_LEFT
        MOV     A, SNAKE_DIR
        CJNE    A, #3, SET_LEFT     
        SJMP    NOT_KEY_LEFT
SET_LEFT:
        MOV     SNAKE_DIR, #2
        SJMP    KEY_DONE

NOT_KEY_LEFT:
        ; --- 檢查「右」方向鍵 (解碼值 6) ---
        CJNE    A, #6, KEY_DONE
        MOV     A, SNAKE_DIR
        CJNE    A, #2, SET_RIGHT    
        SJMP    KEY_DONE
SET_RIGHT:
        MOV     SNAKE_DIR, #3

KEY_DONE:
        ; 2. 檢查定時移動旗標
        MOV     A, MOVE_FLAG
        JZ      GAME_LOOP
        
        MOV     MOVE_FLAG, #0
        ACALL   UPDATE_SNAKE        ; 更新位置、撞牆判定、咬自己判定
        ACALL   REFRESH_SCREEN      ; 刷新螢幕顯示
        
        LJMP    GAME_LOOP

; --------------------------------------------------------------------
; Timer 0 中斷服務常式 (ISR) - 每 50ms 觸發一次
; --------------------------------------------------------------------
T0_ISR:
        PUSH    ACC                 ; ??【關鍵修正】保護主程式的 A 暫存器
        PUSH    PSW                 ; ??【關鍵修正】保護主程式的狀態旗標
        
        MOV     TH0, #3CH
        MOV     TL0, #0B0H
        INC     T0_COUNT
        MOV     A, T0_COUNT
        CJNE    A, #10, T0_EXIT
        
        MOV     T0_COUNT, #0
        MOV     MOVE_FLAG, #1
T0_EXIT:
        POP     PSW                 ; ??【關鍵修正】還原主程式狀態
        POP     ACC                 ; ??【關鍵修正】還原主程式的 A 暫存器
        RETI

; --------------------------------------------------------------------
; 子程式：更新蛇的位置與死亡判定核心邏輯
; --------------------------------------------------------------------
UPDATE_SNAKE:
        MOV     EAT_FLAG, #0        

        ; A. 依據方向計算出下一格蛇頭位置
        MOV     A, SNAKE_DIR
        CJNE    A, #0, U_CHK_DN
        
        ; --- 向上移動 ---
        MOV     A, SNAKE_Y
        JNZ     Y_UP_OK             
        LJMP    GAME_OVER_TRIGGER   
Y_UP_OK:
        DEC     A
        MOV     NEXT_Y, A
        MOV     NEXT_X, SNAKE_X
        SJMP    U_CHK_SELF

U_CHK_DN:
        CJNE    A, #1, U_CHK_LF
        ; --- 向下移動 ---
        MOV     A, SNAKE_Y
        INC     A
        CJNE    A, #2, Y_DN_OK
        LJMP    GAME_OVER_TRIGGER   
Y_DN_OK:
        MOV     NEXT_Y, A
        MOV     NEXT_X, SNAKE_X
        SJMP    U_CHK_SELF

U_CHK_LF:
        CJNE    A, #2, U_CHK_RT
        ; --- 向左移動 ---
        MOV     A, SNAKE_X
        JNZ     X_LF_OK             
        LJMP    GAME_OVER_TRIGGER   
X_LF_OK:
        DEC     A
        MOV     NEXT_X, A
        MOV     NEXT_Y, SNAKE_Y
        SJMP    U_CHK_SELF

U_CHK_RT:
        ; --- 向右移動 ---
        MOV     A, SNAKE_X
        INC     A
        CJNE    A, #16, X_RT_OK     
        LJMP    GAME_OVER_TRIGGER   
X_RT_OK:
        MOV     NEXT_X, A
        MOV     NEXT_Y, SNAKE_Y

; --------------------------------------------------------------------
; B. 死亡判定：檢查是否咬到自己
; --------------------------------------------------------------------
U_CHK_SELF:
        MOV     A, SNAKE_LEN
        DEC     A
        MOV     R0, A               
        MOV     R2, #1              
SELF_LOOP:
        MOV     A, R0
        CLR     C
        SUBB    A, R2
        JC      U_CHK_FOOD          

        MOV     A, #SNAKE_X
        ADD     A, R2
        MOV     R1, A
        MOV     A, @R1
        CJNE    A, NEXT_X, NEXT_NODE
        
        MOV     A, #SNAKE_Y
        ADD     A, R2
        MOV     R1, A
        MOV     A, @R1
        CJNE    A, NEXT_Y, NEXT_NODE
        
        LJMP    GAME_OVER_TRIGGER

NEXT_NODE:
        INC     R2
        SJMP    SELF_LOOP

; --------------------------------------------------------------------
; C. 吃食檢查與身體位移
; --------------------------------------------------------------------
U_CHK_FOOD:
        MOV     A, NEXT_X
        CJNE    A, FOOD_X, NOT_EATEN
        MOV     A, NEXT_Y
        CJNE    A, FOOD_Y, NOT_EATEN
        
        MOV     EAT_FLAG, #1
        INC     SNAKE_LEN
        ACALL   GENERATE_FOOD
        SJMP    DO_SHIFT

NOT_EATEN:
        MOV     A, SNAKE_LEN
        DEC     A
        MOV     R0, A
        
        MOV     A, #SNAKE_X
        ADD     A, R0
        MOV     R1, A
        MOV     TAIL_X, @R1
        
        MOV     A, #SNAKE_Y
        ADD     A, R0
        MOV     R1, A
        MOV     TAIL_Y, @R1

DO_SHIFT:
        MOV     A, SNAKE_LEN
        DEC     A
        MOV     R0, A
U_SHIFT_BODY:
        MOV     A, R0
        JZ      U_SHIFT_DONE
        
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
        MOV     SNAKE_X, NEXT_X
        MOV     SNAKE_Y, NEXT_Y
        RET

; --------------------------------------------------------------------
; ?? GAME OVER 死亡處理觸發器
; --------------------------------------------------------------------
GAME_OVER_TRIGGER:
        CLR     TR0                 
        CLR     EA                  
        
        ACALL   BUZZER_DEATH        
        ACALL   LCD_INIT            
        
        MOV     A, #83H
        ACALL   LCD_CMD
        MOV     A, #'G'
        ACALL   LCD_DATA
        MOV     A, #'a'
        ACALL   LCD_DATA
        MOV     A, #'m'
        ACALL   LCD_DATA
        MOV     A, #'e'
        ACALL   LCD_DATA
        MOV     A, #' '
        ACALL   LCD_DATA
        MOV     A, #'O'
        ACALL   LCD_DATA
        MOV     A, #'v'
        ACALL   LCD_DATA
        MOV     A, #'e'
        ACALL   LCD_DATA
        MOV     A, #'r'
        ACALL   LCD_DATA
        MOV     A, #'!'
        ACALL   LCD_DATA
        
        MOV     A, #0C4H
        ACALL   LCD_CMD
        MOV     A, #'L'
        ACALL   LCD_DATA
        MOV     A, #'e'
        ACALL   LCD_DATA
        MOV     A, #'n'
        ACALL   LCD_DATA
        MOV     A, #':'
        ACALL   LCD_DATA
        
        MOV     A, SNAKE_LEN
        MOV     B, #10
        DIV     AB                  
        JZ      SHOW_DIGIT_1
        ADD     A, #30H             
        ACALL   LCD_DATA
SHOW_DIGIT_1:
        MOV     A, B
        ADD     A, #30H             
        ACALL   LCD_DATA

FREEZE_HERE:
        SJMP    FREEZE_HERE         

; --------------------------------------------------------------------
; 子程式：死亡蜂鳴器控制
; --------------------------------------------------------------------
BUZZER_DEATH:
        MOV     R5, #100            
B_LOOP1:
        CLR     BUZZER              
        ACALL   DELAY_1MS
        SETB    BUZZER              
        ACALL   DELAY_1MS
        DJNZ    R5, B_LOOP1
        
        MOV     R5, #40             
B_LOOP2:
        CLR     BUZZER
        ACALL   DELAY_5MS
        SETB    BUZZER
        ACALL   DELAY_5MS
        DJNZ    R5, B_LOOP2
        RET

; --------------------------------------------------------------------
; 子程式：產生全新隨機食物
; --------------------------------------------------------------------
GENERATE_FOOD:
        MOV     A, SEED_X
        ANL     A, #0FH
        MOV     FOOD_X, A
        
        MOV     A, SEED_Y
        ANL     A, #01H
        MOV     FOOD_Y, A
        
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
        MOV     A, EAT_FLAG
        JNZ     DRAW_HEAD           
        
        MOV     R0, TAIL_X
        MOV     R1, TAIL_Y
        ACALL   GOTO_XY
        MOV     A, #' '
        ACALL   LCD_DATA

DRAW_HEAD:
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
; 子程式：4x4 鍵盤掃描 
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
; 子程式：LCD 驅動與延時基礎常式
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
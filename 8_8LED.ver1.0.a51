; ====================================================================
; 8051 貪食蛇專案 - 純 8x8 點陣 LED 極簡流暢版
; 晶振頻率：12MHz / 適用於標準 Intel 8051 編譯器
; ====================================================================

        ORG     0000H
        LJMP    MAIN
        
        ORG     0003H               ; P3.2 (INT0) 外部中斷（保留可用作暫存或未來擴充）
        LJMP    EX0_ISR

        ORG     000BH               ; Timer 0 中斷進入點
        LJMP    T0_ISR

; --------------------------------------------------------------------
; 常數與硬體腳位定義
; --------------------------------------------------------------------
DATA_PORT   EQU     P0              ; 8x8 點陣列數據控制 (Row Data)
SCAN_PORT   EQU     P1              ; 8x8 點陣行掃描控制 (Column Scan)
BUZZER      EQU     P2.6            ; 蜂鳴器接在 P2.7

; --------------------------------------------------------------------
; RAM 位置分配
; --------------------------------------------------------------------
VRAM_START  EQU     30H             ; 8x8 點陣動態顯存區域 (30H~37H)

SNAKE_LEN   EQU     41H             ; 蛇目前長度
SNAKE_DIR   EQU     42H             ; 方向 (0:上, 1:下, 2:左, 3:右)
MOVE_FLAG   EQU     43H             ; 移動驅動旗標
T0_COUNT    EQU     44H             ; 中斷計數器
TAIL_X      EQU     45H             ; 舊蛇尾暫存 X
TAIL_Y      EQU     46H             ; 舊蛇尾暫存 Y
NEXT_X      EQU     47H             ; 下一格預期蛇頭 X
NEXT_Y      EQU     48H             ; 下一格預期蛇頭 Y
FOOD_X      EQU     49H             ; 食物 X 座標 (0~7)
FOOD_Y      EQU     4AH             ; 食物 Y 座標 (0~7)
EAT_FLAG    EQU     4BH             ; 是否吃到食物旗標
SEED_X      EQU     4CH             ; 隨機數種子 X
SEED_Y      EQU     4DH             ; 隨機數種子 Y

SNAKE_X     EQU     50H             ; 蛇身 X 陣列起點 (50H=頭)
SNAKE_Y     EQU     60H             ; 蛇身 Y 陣列起點 (60H=頭)

; --------------------------------------------------------------------
; 主程式初始化
; --------------------------------------------------------------------
MAIN:
        MOV     SP, #70H            ; 堆疊移至安全高位
        SETB    BUZZER              ; 讓蜂鳴器一開始保持安靜
        
        ; 關閉所有顯示硬體，進入純淨狀態
        MOV     DATA_PORT, #0FFH
        MOV     SCAN_PORT, #0FFH
        ACALL   DELAY_50MS

        ; --- 初始化遊戲數據 ---
        MOV     SNAKE_LEN, #3       ; 初始長度為 3
        MOV     SNAKE_DIR, #3       ; 初始方向向右 (對應實體移動)
        MOV     MOVE_FLAG, #0
        MOV     T0_COUNT, #0
        MOV     EAT_FLAG, #0
        MOV     SEED_X, #13
        MOV     SEED_Y, #7

        ; 設定初始蛇身坐標 (置中於 8x8 安全範圍內)
        MOV     SNAKE_X, #3
        MOV     SNAKE_Y, #3
        MOV     51H, #2
        MOV     61H, #3
        MOV     52H, #1
        MOV     62H, #3

        ; 初始化第一個食物的位置 (5, 5)
        MOV     FOOD_X, #5
        MOV     FOOD_Y, #5

        ; 繪製初始畫面
        ACALL   MAP_UPDATE

        ; --- 初始化 P3.2 外部中斷 (INT0) ---
        SETB    IT0                 ; 設定 INT0 為負邊緣觸發
        SETB    EX0                 ; 開啟外部中斷 0
        
        ; --- 初始化 Timer 0 (50ms 中斷一次) ---
        MOV     TMOD, #01H
        MOV     TH0, #3CH
        MOV     TL0, #0B0H
        SETB    ET0
        SETB    EA                  ; 開啟全局中斷
        SETB    TR0                 ; 啟動計時器

; --------------------------------------------------------------------
; 遊戲主迴圈
; --------------------------------------------------------------------
GAME_LOOP:
        INC     SEED_X              ; 隨機種子累加
        MOV     A, SEED_Y
        ADD     A, #3
        MOV     SEED_Y, A

        ; ?? 持續進行動態掃描刷新 8x8 點陣
        ACALL   LED_MATRIX_SCAN     

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
        ; 2. 檢查定時移動旗標 (每 500ms 移動一格)
        MOV     A, MOVE_FLAG
        JZ      GAME_LOOP
        
        MOV     MOVE_FLAG, #0
        ACALL   UPDATE_SNAKE        ; 更新位置與碰撞判定
        ACALL   MAP_UPDATE          ; 重新繪製 VRAM 顯存
        
        LJMP    GAME_LOOP

; --------------------------------------------------------------------
; 外部中斷 0 服務常式 (P3.2 按下時觸發，目前保留供彈性使用)
; --------------------------------------------------------------------
EX0_ISR:
        RETI

; --------------------------------------------------------------------
; Timer 0 中斷服務常式 - 每 50ms 觸發一次
; --------------------------------------------------------------------
T0_ISR:
        PUSH    ACC                 
        PUSH    PSW                 
        
        MOV     TH0, #3CH
        MOV     TL0, #0B0H
        INC     T0_COUNT
        MOV     A, T0_COUNT
        CJNE    A, #10, T0_EXIT     ; 計數滿 10 次 (500ms) 走一步
        
        MOV     T0_COUNT, #0
        MOV     MOVE_FLAG, #1
T0_EXIT:
        POP     PSW                 
        POP     ACC                 
        RETI

; --------------------------------------------------------------------
; 子程式：更新蛇的位置與死亡判定 (針對點陣進行硬體方向補正)
; --------------------------------------------------------------------
UPDATE_SNAKE:
        MOV     EAT_FLAG, #0        

        ; 根據你的實體點陣反轉回饋，做 90 度方向補正：
        ; 玩家按上(0) -> 實體往右移動 (X++)
        ; 玩家按下(1) -> 實體往左移動 (X--)
        ; 玩家按左(2) -> 實體往上移動 (Y--)
        ; 玩家按右(3) -> 實體往下移動 (Y++)
        MOV     A, SNAKE_DIR
        CJNE    A, #0, LED_CHK_DN
        LJMP    MOVE_X_INC          
LED_CHK_DN:
        CJNE    A, #1, LED_CHK_LF
        LJMP    MOVE_X_DEC          
LED_CHK_LF:
        CJNE    A, #2, LED_CHK_RT
        LJMP    MOVE_Y_DEC          
LED_CHK_RT:
        LJMP    MOVE_Y_INC          

; --- 實際座標增減與 8x8 撞牆死判定 ---
MOVE_Y_DEC:
        MOV     A, SNAKE_Y
        JNZ     Y_UP_OK             
        LJMP    GAME_OVER_TRIGGER   ; 撞上牆壁死
Y_UP_OK:
        DEC     A
        MOV     NEXT_Y, A
        MOV     NEXT_X, SNAKE_X
        LJMP    U_CHK_SELF

MOVE_Y_INC:
        MOV     A, SNAKE_Y
        INC     A
        CJNE    A, #8, Y_DN_OK      ; 邊界最大 7
        LJMP    GAME_OVER_TRIGGER   
Y_DN_OK:
        MOV     NEXT_Y, A
        MOV     NEXT_X, SNAKE_X
        LJMP    U_CHK_SELF

MOVE_X_DEC:
        MOV     A, SNAKE_X
        JNZ     X_LF_OK             
        LJMP    GAME_OVER_TRIGGER   
X_LF_OK:
        DEC     A
        MOV     NEXT_X, A
        MOV     NEXT_Y, SNAKE_Y
        LJMP    U_CHK_SELF

MOVE_X_INC:
        MOV     A, SNAKE_X
        INC     A
        CJNE    A, #8, X_RT_OK      
        LJMP    GAME_OVER_TRIGGER   
X_RT_OK:
        MOV     NEXT_X, A
        MOV     NEXT_Y, SNAKE_Y

; 檢查是否咬到自己
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

; 檢查是否吃到食物與蛇身位移
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
; ?? GAME OVER 處理
; --------------------------------------------------------------------
GAME_OVER_TRIGGER:
        CLR     TR0                 ; 停止計時器
        CLR     EA                  ; 關閉所有中編譯中斷
        
        ACALL   BUZZER_DEATH        ; 觸發死亡音效

FREEZE_HERE:
        ; 死亡時，畫面保持鎖定並持續刷新點陣，呈現在撞牆/咬到的最後一幕
        ACALL   LED_MATRIX_SCAN
        SJMP    FREEZE_HERE         

; --------------------------------------------------------------------
; 子程式：死亡聲音控制
; --------------------------------------------------------------------
BUZZER_DEATH:
        MOV     R5, #100            
B_LOOP1:
        CLR     BUZZER              
        ACALL   DELAY_1MS
        SETB    BUZZER              
        ACALL   DELAY_1MS
        DJNZ    R5, B_LOOP1
        RET

; --------------------------------------------------------------------
; 子程式：產生隨機食物 (0~7)
; --------------------------------------------------------------------
GENERATE_FOOD:
        MOV     A, SEED_X
        ANL     A, #07H
        MOV     FOOD_X, A
        MOV     A, SEED_Y
        ANL     A, #07H
        MOV     FOOD_Y, A
        RET

; --------------------------------------------------------------------
; 子程式：渲染運算 (計算完畢後寫入 VRAM 顯存 30H~37H)
; --------------------------------------------------------------------
MAP_UPDATE:
        ; 1. 先把 8x8 VRAM 全清為全暗 (常規 1 為滅)
        MOV     R0, #VRAM_START
        MOV     R7, #8
CLEAR_VRAM_LOOP:
        MOV     @R0, #11111111B
        INC     R0
        DJNZ    R7, CLEAR_VRAM_LOOP

        ; 2. 在顯存中點亮食物位置
        MOV     A, #VRAM_START
        ADD     A, FOOD_Y
        MOV     R0, A
        MOV     A, #0FEH            ; 11111110B
        MOV     R2, FOOD_X
        JZ      F_BIT_OK
F_BIT_LP:
        RL      A                   
        DJNZ    R2, F_BIT_LP
F_BIT_OK:
        MOV     R6, A
        MOV     A, @R0
        ANL     A, R6               ; 藉由 A 中轉，符合 8051 指令集規範
        MOV     @R0, A

        ; 3. 在顯存中點亮所有蛇身節點
        MOV     R3, #0              
RENDER_SNAKE_LOOP:
        MOV     A, #SNAKE_X
        ADD     A, R3
        MOV     R0, A
        MOV     A, @R0
        MOV     R4, A               ; R4 = 當前身體 X

        MOV     A, #SNAKE_Y
        ADD     A, R3
        MOV     R0, A
        MOV     A, @R0
        MOV     R5, A               ; R5 = 當前身體 Y

        ; 轉換至 VRAM 位元寫入
        MOV     A, #VRAM_START
        ADD     A, R5
        MOV     R0, A
        MOV     A, #0FEH
        MOV     R2, R4
        JZ      S_BIT_OK
S_BIT_LP:
        RL      A
        DJNZ    R2, S_BIT_LP
S_BIT_OK:
        MOV     R6, A
        MOV     A, @R0
        ANL     A, R6
        MOV     @R0, A

        INC     R3
        MOV     A, R3
        CJNE    A, SNAKE_LEN, RENDER_SNAKE_LOOP
        RET

; --------------------------------------------------------------------
; 子程式：8x8 點陣 LED 高速動態掃描驅動 (無殘影、穩定)
; --------------------------------------------------------------------
LED_MATRIX_SCAN:
        MOV     R1, #VRAM_START     
        MOV     R5, #11111110B      ; 從行 0 開始選通
        MOV     R4, #8              

LED_LOOP1:
        MOV     A, @R1              
        MOV     DATA_PORT, A        ; 將該行數據送出至 P0
        MOV     SCAN_PORT, R5       ; 將選通訊號送出至 P1
        
        ; 點亮維持時間
        MOV     R6, #2
L_DL1:  MOV     R7, #100
        DJNZ    R7, $
        DJNZ    R6, L_DL1
        
        ORL     SCAN_PORT, #11111111B ; ?? 徹底消影：關閉行選通，防殘影鬼影
        
        MOV     A, R5
        RL      A                   ; 左移進入下一行選通
        MOV     R5, A
        INC     R1                  ; 記憶體指標指向下一個顯存位元組
        DJNZ    R4, LED_LOOP1
        RET

; --------------------------------------------------------------------
; 子程式：4x4 鍵盤掃描 (時分隔離防干擾技術)
; --------------------------------------------------------------------
KEY_SCAN:
        MOV     DATA_PORT, #0FFH    ; ?? 鍵盤掃描前切斷點陣的數據通路
        MOV     SCAN_PORT, #0FFH    ; 釋放 P1 腳位供鍵盤使用

        ; 掃描 Row 0
        CLR     P1.0
        SETB    P1.1
        SETB    P1.2
        SETB    P1.3
        MOV     A, P2
        ANL     A, #0FH
        CJNE    A, #0FH, R0_HIT

        ; 掃描 Row 1
        SETB    P1.0
        CLR     P1.1
        SETB    P1.2
        SETB    P1.3
        MOV     A, P2
        ANL     A, #0FH
        CJNE    A, #0FH, R1_HIT

        ; 掃描 Row 2
        SETB    P1.0
        SETB    P1.1
        CLR     P1.2
        SETB    P1.3
        MOV     A, P2
        ANL     A, #0FH
        CJNE    A, #0FH, R2_HIT

        ; 掃描 Row 3
        SETB    P1.0
        SETB    P1.1
        SETB    P1.2
        CLR     P1.3
        MOV     A, P2
        ANL     A, #0FH
        CJNE    A, #0FH, R3_HIT

        MOV     A, #0FFH            ; 沒有按鍵按下
        RET

R0_HIT:
        MOV     R2, #0
        LJMP    DECODE_COL
R1_HIT:
        MOV     R2, #4
        LJMP    DECODE_COL
R2_HIT:
        MOV     R2, #8
        LJMP    DECODE_COL
R3_HIT:
        MOV     R2, #12
        LJMP    DECODE_COL

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
; 基礎延時常式
; --------------------------------------------------------------------
DELAY_1MS:
        MOV     R7, #2
D1:     MOV     R6, #250
        DJNZ    R6, $
        DJNZ    R7, D1
        RET

DELAY_50MS:
        MOV     R4, #250
D50_1:  MOV     R3, #100
        DJNZ    R3, $
        DJNZ    R4, D50_1
        RET

        END
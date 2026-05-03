module UART#(
    parameter CLK_FREQ = 50_000_000,    // 系统时钟频率，单位Hz（默认50MHz）
    parameter BAUD = 9600               // UART波特率（默认9600bps）
)
(
    input CLK,                          // 系统时钟输入
    input RESET_N,                      // 低电平有效的复位信号
    input RESET_GO,                     // 外部手动发送触发信号（高电平有效）
    input MODE,                         // 模式控制：0=自动定时发送模式，1=外部手动触发模式
    input [7:0] DATE,                   // 待发送的8位并行数据
    output reg TX,                      // UART串行数据发送输出端
    output reg LED                      // LED指示灯，发送一帧数据后翻转一次
);
    reg [12:0] COUNTER1;                // 波特率分频计数器，用于产生9600波特率的位定时
    reg [25:0] COUNTER2;                // 1秒定时计数器，用于自动模式下定时触发发送
    reg [3:0]  COUNTER3;                // 发送位计数器，0-9对应起始位、8位数据、停止位
    reg EN_C1;                          // 发送使能标志，高电平表示正在发送一帧数据
    reg [7:0] SAVE;                     // 数据锁存寄存器，保存当前待发送的8位数据
    reg DOWN;                           // 一帧发送完毕标志，发送完停止位后置1
    reg BUSY;                           // 发送忙标志，高电平表示当前正在发送中，用于互锁

    localparam DIV = CLK_FREQ/BAUD;     // 波特率分频系数，计算每位的时钟周期数（50M/9600≈5208）

    // 波特率9600产生及发送状态控制
    // 功能：对系统时钟分频产生9600波特率，并控制发送10个位（1起始+8数据+1停止）
    always@(posedge CLK or negedge RESET_N) begin
        if(!RESET_N) begin               // 复位时清零所有状态
            COUNTER1 <= 0;               // 波特率计数器清零
            COUNTER3 <= 0;               // 位计数器清零
            DOWN <= 0;                   // 发送完成标志清零
            LED <= 0;                    // LED熄灭
        end
        else if(EN_C1)begin              // 发送使能有效时，进行波特率计数和位发送控制
            if(COUNTER1 == DIV - 1) begin // 计数到分频系数个时钟周期，完成一位发送
                COUNTER1 <= 0;            // 波特率计数器清零，准备下一位
                if(COUNTER3 == 9) begin   // 已发送完10个位（0-9）
                    COUNTER3 <= 0;          // 位计数器清零
                    DOWN <= 1;              // 置发送完成标志
                    LED <= ~LED;            // LED状态翻转，指示完成一帧发送
                end
                else COUNTER3 <= COUNTER3 + 1'b1;  // 位计数器加1，发送下一位
            end
            else COUNTER1 <= COUNTER1 + 1'b1;      // 波特率计数器继续计数
        end
        else begin                       // 发送未启动或已停止
            COUNTER1 <= 0;               // 波特率计数器清零
            COUNTER3 <= 0;               // 位计数器清零
            DOWN <= 0;                   // 发送完成标志清零
        end
    end

    // 发送控制逻辑（内控/外控模式切换 + 互锁机制）
    // 功能：根据MODE选择自动定时发送或外部触发发送，通过BUSY标志实现互锁
    always@(posedge CLK or negedge RESET_N) begin
        if(!RESET_N) begin               // 复位时清零
            COUNTER2 <= 0;               // 1秒定时器清零
            SAVE <= 0;                   // 数据锁存清零
            EN_C1 <= 0;                  // 发送使能关闭
            BUSY <= 0;                   // 忙标志清零
        end
        else begin
            if(DOWN) begin               // 检测到发送完成标志（来自波特率always块）
                EN_C1 <= 0;              // 关闭发送使能，停止发送
                BUSY <= 0;               // 清除忙标志，允许下一次发送
            end
            if(!BUSY) begin              // 仅在空闲状态（非忙）时才允许启动新发送
                if(MODE == 0) begin      // 模式0：自动定时发送模式
                    if(COUNTER2 == 50_000_000 - 1) begin  // 计数到1秒（50M个时钟周期）
                        COUNTER2 <= 0;                   // 1秒计数器清零
                        SAVE <= DATE;                    // 锁存当前待发送数据
                        EN_C1 <= 1;                      // 启动发送使能
                        BUSY <= 1;                       // 置忙标志，锁住发送通道
                    end
                    else COUNTER2 <= COUNTER2 + 1'b1;    // 1秒计数器继续计数
                end
                else begin               // 模式1：外部手动触发发送模式
                    if(RESET_GO) begin   // 检测到外部发送触发信号
                        COUNTER2 <= 0;   // 清零1秒计数器（手动模式下不使用）
                        SAVE <= DATE;    // 锁存当前待发送数据
                        EN_C1 <= 1;      // 启动发送使能
                        BUSY <= 1;       // 置忙标志，防止重复触发
                    end
                end
            end
        end
    end

    // UART串行数据输出
    // 功能：根据位计数器COUNTER3，将并行数据SAVE转为串行输出
    // UART帧格式：起始位(0) + D0-D7(低位先发) + 停止位(1)
    always@(posedge CLK or negedge RESET_N) begin
        if(!RESET_N) TX <= 1'b1;         // 复位时TX置高电平（UART空闲状态为高）
        else begin
            if(EN_C1)                    // 发送使能有效时，按位输出
            case(COUNTER3)
                0:TX <= 1'b0;              // 第0位：起始位，低电平
                1:TX <= SAVE[0];           // 第1位：数据最低位D0
                2:TX <= SAVE[1];           // 第2位：数据位D1
                3:TX <= SAVE[2];           // 第3位：数据位D2
                4:TX <= SAVE[3];           // 第4位：数据位D3

                5:TX <= SAVE[4];           // 第5位：数据位D4
                6:TX <= SAVE[5];           // 第6位：数据位D5
                7:TX <= SAVE[6];           // 第7位：数据位D6
                8:TX <= SAVE[7];           // 第8位：数据最高位D7
                9:TX <= 1'b1;              // 第9位：停止位，高电平
            endcase
            else TX <= 1'b1;             // 空闲时TX保持高电平（UART协议要求）
        end
    end
endmodule
//+------------------------------------------------------------------+
//|                                   NTA_DailyLiquidityStory.mq5    |
//|  DAILY LIQUIDITY STORY                                           |
//|  ASIA -> LONDON -> NEW YORK liquidity sequence state machine     |
//|                                                                  |
//|  Market story first, not buy/sell signals:                       |
//|   1. Where did Asia create liquidity?                            |
//|   2. Which Asia liquidity did London take (sweep vs breakout)?   |
//|   3. Where did London leave liquidity?                           |
//|   4. Which liquidity is New York targeting?                      |
//|   5. Did NY sweep or truly break out?                            |
//|   6. Displacement after the sweep?                               |
//|   7. Market structure shift?                                     |
//|   8. FVG created?                                                |
//|   9. Retrace into the imbalance?                                 |
//|  10. Inside a Silver Bullet window? (tag only)                   |
//|                                                                  |
//|  Only closed bars are evaluated: locked levels never repaint.    |
//+------------------------------------------------------------------+
#property copyright   "NTA"
#property version     "1.00"
#property description "Daily Liquidity Story: Asia -> London -> New York liquidity sequence."
#property description "Sweep vs breakout, displacement, MSS, story FVG, retrace, statistics."
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   8

#property indicator_label1 "DLS State"
#property indicator_type1  DRAW_NONE
#property indicator_label2 "DLS Story Dir"
#property indicator_type2  DRAW_NONE
#property indicator_label3 "DLS Asia High"
#property indicator_type3  DRAW_NONE
#property indicator_label4 "DLS Asia Low"
#property indicator_type4  DRAW_NONE
#property indicator_label5 "DLS London High"
#property indicator_type5  DRAW_NONE
#property indicator_label6 "DLS London Low"
#property indicator_type6  DRAW_NONE
#property indicator_label7 "DLS Story FVG Top"
#property indicator_type7  DRAW_NONE
#property indicator_label8 "DLS Story FVG Bottom"
#property indicator_type8  DRAW_NONE

#include <NTA/DailyLiquidityStory/DLS_Engine.mqh>
#include <NTA/DailyLiquidityStory/DLS_Stats.mqh>
#include <NTA/DailyLiquidityStory/DLS_Renderer.mqh>

//--- time
input group "=== Time (all session times are New York time) ==="
input int      InpServerToNyHours = -7;        // NY time = server time + N hours (GMT+3 broker in US DST: -7)
input string   InpDayStart        = "18:00";   // Story day start (NY)
input string   InpAsiaStart       = "20:00";   // Asian Kill Zone start
input string   InpAsiaEnd         = "00:00";   // Asian Kill Zone end
input string   InpLondonStart     = "02:00";   // London Kill Zone start
input string   InpLondonEnd       = "05:00";   // London Kill Zone end
input string   InpNyStart         = "07:00";   // NY liquidity window start (sweeps monitored)
input string   InpNyEnd           = "11:00";   // NY liquidity window end (no new sweeps after)
input string   InpNyCutoff        = "12:00";   // NY development cutoff (disp/MSS/FVG/retrace)
input string   InpEvalEnd         = "16:00";   // MFE / MAE evaluation end

input group "=== Silver Bullet windows (tag only, logic unchanged) ==="
input bool     InpSbAm            = true;      // NY AM Silver Bullet
input string   InpSbAmStart       = "10:00";
input string   InpSbAmEnd         = "11:00";
input bool     InpSbPm            = true;      // NY PM Silver Bullet
input string   InpSbPmStart       = "14:00";
input string   InpSbPmEnd         = "15:00";
input bool     InpSbLon           = false;     // London Silver Bullet
input string   InpSbLonStart      = "03:00";
input string   InpSbLonEnd        = "04:00";

input group "=== Sweep vs breakout ==="
input ENUM_DLS_BUFFER_MODE InpBufferMode = DLS_BUF_ATR; // SweepBuffer mode
input double   InpSweepBuffer     = 0.05;      // SweepBuffer (price, or x chart ATR)
input int      InpAcceptBars      = 2;         // Consecutive closes beyond = BROKEN / ACCEPTED

input group "=== Asia range quality ==="
input ENUM_TIMEFRAMES InpRangeAtrTf = PERIOD_D1; // ATR timeframe for AsiaRange / ATR
input int      InpRangeAtrPeriod  = 14;        // ATR period for AsiaRange / ATR
input double   InpNarrowRatio     = 0.30;      // NARROW if ratio below
input double   InpWideRatio       = 0.60;      // WIDE if ratio above

input group "=== Displacement ==="
input int      InpAtrPeriod       = 14;        // ATRPeriod (chart timeframe)
input ENUM_DLS_DISP_MODE InpDispMode = DLS_DISP_BOTH; // Displacement rule
input double   InpDispAtrFactor   = 1.0;       // DisplacementATRFactor (body >= ATR x)
input int      InpAvgBodyPeriod   = 20;        // AverageBodyPeriod
input double   InpBodyMultiplier  = 1.5;       // BodyMultiplier (body >= avg body x)
input int      InpDispMaxBars     = 12;        // Max bars from sweep to displacement

input group "=== Market structure shift ==="
input int      InpSwingStrength   = 2;         // Swing fractal strength (bars each side)
input int      InpMssSwingLookback = 40;       // Max bars back for the MSS swing
input int      InpMssMaxBars      = 20;        // Max bars from displacement to MSS close

input group "=== FVG / retrace ==="
input double   InpFvgMinAtr       = 0.10;      // Min FVG size (x ATR)
input int      InpFvgMaxBars      = 10;        // Max bars after MSS to find the story FVG
input bool     InpFvgAfterMssOnly = false;     // Only FVGs formed after the MSS close
input ENUM_DLS_RETRACE_LEVEL InpRetraceLevel = DLS_RT_CE; // Retrace level

input group "=== History / statistics ==="
input int      InpLookbackDays    = 60;        // Days of history to evaluate
input bool     InpExportCsv       = true;      // Export per-day story CSV (MQL5/Files)
input bool     InpCsvCommon       = false;     // Write CSV to the common Files folder
input bool     InpJournal         = false;     // Print live story events to the Experts log

input group "=== Display ==="
input int      InpDrawDays        = 3;         // Days drawn on chart
input bool     InpShowPanel       = true;      // Story timeline panel
input bool     InpShowStats       = true;      // Statistics block in the panel
input bool     InpShowLabels      = true;      // Chart story labels
input bool     InpShowPath        = true;      // Dotted story path
input bool     InpShowNormalFvg   = true;      // Draw normal (non-story) FVGs
input int      InpNormalFvgBars   = 6;         // Normal FVG box length (bars)
input bool     InpShowPdLevels    = true;      // Draw PDH / PDL
input bool     InpShowSwingTargets = true;     // Draw swing targets used by NY
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER;
input int      InpPanelX          = 10;
input int      InpPanelY          = 25;
input int      InpPanelWidth      = 330;
input string   InpPanelFont       = "Consolas";
input int      InpPanelFontSize   = 8;
input int      InpLabelFontSize   = 7;
input ENUM_DLS_LABEL_MODE InpLabelMode = DLS_LABELS_COMPACT; // Chart label detail
input int      InpLabelDays       = 1;         // Days (newest first) with text labels
input bool     InpAvoidOverlap    = true;      // Stack colliding labels (re-laid out on zoom/scroll)

input group "=== Colors ==="
input color    InpAsiaBox         = C'32,42,72';
input color    InpLondonBox       = C'70,46,32';
input color    InpBslColor        = clrTomato;
input color    InpSslColor        = clrDeepSkyBlue;
input color    InpPdColor         = clrSlateGray;
input color    InpSwingColor      = clrDarkKhaki;
input color    InpBearColor       = clrCrimson;
input color    InpBullColor       = clrLimeGreen;
input color    InpNeutralColor    = clrSilver;
input color    InpNormalFvg       = C'45,45,50';
input color    InpStoryFvgBear    = C'105,30,45';
input color    InpStoryFvgBull    = C'25,90,55';
input color    InpTextColor       = clrSilver;
input color    InpPanelBg         = C'18,20,26';
input color    InpPanelBorder     = C'70,70,80';
input color    InpPanelText       = clrGainsboro;
input color    InpPanelHeader     = clrGold;
input color    InpPanelOk         = clrLimeGreen;
input color    InpPanelWait       = clrOrange;
input color    InpPanelFail       = clrTomato;
input color    InpPanelMuted      = clrGray;

//--- buffers (Data Window / iCustom access for an EA)
double BufState[], BufDir[], BufAsiaH[], BufAsiaL[], BufLonH[], BufLonL[], BufFvgTop[], BufFvgBot[];

CDlsEngine   g_eng;
CDlsStats    g_stats;
CDlsRenderer g_draw;
int          g_refAtrHandle = INVALID_HANDLE;
int          g_lastIdx = -1;
bool         g_built = false;
datetime     g_refStart = 0, g_refEnd = 0;
double       g_refVal = 0;
string       g_statLines[];

//+------------------------------------------------------------------+
int ParseOrFail(const string v, const string name, bool &ok)
  {
   int m = DlsParseHHMM(v);
   if(m < 0)
     {
      PrintFormat("NTA DLS: invalid time '%s' for %s (use HH:MM)", v, name);
      ok = false;
     }
   return m;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   bool ok = true;
   SDlsSettings s;
   ZeroMemory(s);
   s.serverToNyHours = InpServerToNyHours;
   s.dayStartMin  = ParseOrFail(InpDayStart, "DayStart", ok);
   s.asiaStart    = ParseOrFail(InpAsiaStart, "AsiaStart", ok);
   s.asiaEnd      = ParseOrFail(InpAsiaEnd, "AsiaEnd", ok);
   s.londonStart  = ParseOrFail(InpLondonStart, "LondonStart", ok);
   s.londonEnd    = ParseOrFail(InpLondonEnd, "LondonEnd", ok);
   s.nyStart      = ParseOrFail(InpNyStart, "NyStart", ok);
   s.nyEnd        = ParseOrFail(InpNyEnd, "NyEnd", ok);
   s.nyCutoff     = ParseOrFail(InpNyCutoff, "NyCutoff", ok);
   s.evalEnd      = ParseOrFail(InpEvalEnd, "EvalEnd", ok);
   s.sbAmOn = InpSbAm;   s.sbAmStart  = ParseOrFail(InpSbAmStart, "SbAmStart", ok);   s.sbAmEnd  = ParseOrFail(InpSbAmEnd, "SbAmEnd", ok);
   s.sbPmOn = InpSbPm;   s.sbPmStart  = ParseOrFail(InpSbPmStart, "SbPmStart", ok);   s.sbPmEnd  = ParseOrFail(InpSbPmEnd, "SbPmEnd", ok);
   s.sbLonOn = InpSbLon; s.sbLonStart = ParseOrFail(InpSbLonStart, "SbLonStart", ok); s.sbLonEnd = ParseOrFail(InpSbLonEnd, "SbLonEnd", ok);
   if(!ok)
      return INIT_PARAMETERS_INCORRECT;

   s.bufferMode      = InpBufferMode;
   s.bufferValue     = InpSweepBuffer;
   s.acceptBars      = InpAcceptBars;
   s.narrowRatio     = InpNarrowRatio;
   s.wideRatio       = InpWideRatio;
   s.atrPeriod       = InpAtrPeriod;
   s.dispMode        = InpDispMode;
   s.dispAtrFactor   = InpDispAtrFactor;
   s.avgBodyPeriod   = InpAvgBodyPeriod;
   s.bodyMultiplier  = InpBodyMultiplier;
   s.dispMaxBars     = InpDispMaxBars;
   s.swingStrength   = InpSwingStrength;
   s.mssSwingLookback = InpMssSwingLookback;
   s.mssMaxBars      = InpMssMaxBars;
   s.fvgMinAtr       = InpFvgMinAtr;
   s.fvgMaxBars      = InpFvgMaxBars;
   s.fvgAfterMssOnly = InpFvgAfterMssOnly;
   s.retraceLevel    = InpRetraceLevel;

   g_eng.Init(s, PeriodSeconds(_Period));
   string why;
   if(!g_eng.WindowsValid(why))
     {
      Print("NTA DLS: ", why);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpNarrowRatio >= InpWideRatio)
     {
      Print("NTA DLS: NarrowRatio must be below WideRatio");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(PeriodSeconds(_Period) > 3600)
      Print("NTA DLS: designed for M1-H1 charts; sessions are too coarse above H1.");
   g_eng.journalPrefix = "NTA DLS " + _Symbol + " ";

   g_refAtrHandle = iATR(_Symbol, InpRangeAtrTf, InpRangeAtrPeriod);
   if(g_refAtrHandle == INVALID_HANDLE)
     {
      Print("NTA DLS: cannot create reference ATR");
      return INIT_FAILED;
     }

   SDlsStyle st;
   st.asiaBox = InpAsiaBox;          st.londonBox = InpLondonBox;
   st.bslColor = InpBslColor;        st.sslColor = InpSslColor;
   st.pdColor = InpPdColor;          st.swingColor = InpSwingColor;
   st.bearColor = InpBearColor;      st.bullColor = InpBullColor;     st.neutralColor = InpNeutralColor;
   st.normalFvg = InpNormalFvg;      st.storyFvgBear = InpStoryFvgBear; st.storyFvgBull = InpStoryFvgBull;
   st.textColor = InpTextColor;
   st.panelBg = InpPanelBg;          st.panelBorder = InpPanelBorder; st.panelText = InpPanelText;
   st.panelHeader = InpPanelHeader;  st.panelOk = InpPanelOk;         st.panelWait = InpPanelWait;
   st.panelFail = InpPanelFail;      st.panelMuted = InpPanelMuted;
   st.labelFontSize = InpLabelFontSize;
   st.panelFont = InpPanelFont;      st.panelFontSize = InpPanelFontSize;
   st.panelCorner = InpPanelCorner;  st.panelX = InpPanelX; st.panelY = InpPanelY; st.panelWidth = InpPanelWidth;
   st.showPanel = InpShowPanel;      st.showStats = InpShowStats;     st.showLabels = InpShowLabels;
   st.showPath = InpShowPath;        st.showNormalFvg = InpShowNormalFvg;
   st.showPdLevels = InpShowPdLevels; st.showSwingTargets = InpShowSwingTargets;
   st.normalFvgBars = InpNormalFvgBars;
   st.labelMode = InpLabelMode;
   st.labelDays = MathMax(0, InpLabelDays);
   st.avoidOverlap = InpAvoidOverlap;
   g_draw.Init(st, 0);

   SetIndexBuffer(0, BufState,  INDICATOR_DATA);
   SetIndexBuffer(1, BufDir,    INDICATOR_DATA);
   SetIndexBuffer(2, BufAsiaH,  INDICATOR_DATA);
   SetIndexBuffer(3, BufAsiaL,  INDICATOR_DATA);
   SetIndexBuffer(4, BufLonH,   INDICATOR_DATA);
   SetIndexBuffer(5, BufLonL,   INDICATOR_DATA);
   SetIndexBuffer(6, BufFvgTop, INDICATOR_DATA);
   SetIndexBuffer(7, BufFvgBot, INDICATOR_DATA);
   for(int b = 0; b < 8; b++)
      PlotIndexSetDouble(b, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "NTA Daily Liquidity Story");
   g_built = false;
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_draw.DeleteAll();
   if(g_refAtrHandle != INVALID_HANDLE)
      IndicatorRelease(g_refAtrHandle);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Reference ATR (previous completed bar of InpRangeAtrTf)           |
//+------------------------------------------------------------------+
double RefAtr(const datetime t)
  {
   if(t >= g_refStart && t < g_refEnd)
      return g_refVal;
   int sh = iBarShift(_Symbol, InpRangeAtrTf, t, false);
   g_refVal = 0;
   if(sh < 0)
      return 0;
   g_refStart = iTime(_Symbol, InpRangeAtrTf, sh);
   g_refEnd = g_refStart + PeriodSeconds(InpRangeAtrTf);
   double b[1];
   if(CopyBuffer(g_refAtrHandle, 0, sh + 1, 1, b) == 1 && b[0] != EMPTY_VALUE)
      g_refVal = b[0];
   return g_refVal;
  }

//+------------------------------------------------------------------+
bool WithLabels(const int dayIdx)
  {
   return dayIdx >= g_eng.dayCount - InpLabelDays;
  }

//+------------------------------------------------------------------+
//| Zoom / scroll changes pixel distances: lay the labels out again   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_CHART_CHANGE || !g_built || !InpAvoidOverlap)
      return;
   g_draw.Layout();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
void WriteBuffers(const int i)
  {
   int cur = g_eng.dayCount - 1;
   if(cur < 0)
      return;
   BufState[i] = g_eng.days[cur].state;
   BufDir[i]   = g_eng.days[cur].committed ? g_eng.days[cur].story.dir : 0;
   BufAsiaH[i] = g_eng.days[cur].asiaStarted ? g_eng.days[cur].asiaHigh : EMPTY_VALUE;
   BufAsiaL[i] = g_eng.days[cur].asiaStarted ? g_eng.days[cur].asiaLow  : EMPTY_VALUE;
   BufLonH[i]  = g_eng.days[cur].lonStarted  ? g_eng.days[cur].lonHigh  : EMPTY_VALUE;
   BufLonL[i]  = g_eng.days[cur].lonStarted  ? g_eng.days[cur].lonLow   : EMPTY_VALUE;
   bool fvg = g_eng.days[cur].fFvg;
   BufFvgTop[i] = fvg ? g_eng.days[cur].story.fvgTop    : EMPTY_VALUE;
   BufFvgBot[i] = fvg ? g_eng.days[cur].story.fvgBottom : EMPTY_VALUE;
  }

void ClearBuffers(const int from, const int to)
  {
   for(int i = from; i <= to; i++)
     {
      BufState[i] = EMPTY_VALUE; BufDir[i] = EMPTY_VALUE;
      BufAsiaH[i] = EMPTY_VALUE; BufAsiaL[i] = EMPTY_VALUE;
      BufLonH[i] = EMPTY_VALUE;  BufLonL[i] = EMPTY_VALUE;
      BufFvgTop[i] = EMPTY_VALUE; BufFvgBot[i] = EMPTY_VALUE;
     }
  }

void RefreshStats()
  {
   g_stats.Compute(g_eng);
   g_stats.Lines(g_statLines);
   if(InpExportCsv)
     {
      string tf = StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7);
      g_stats.ExportCsv(g_eng, "NTA_DLS_" + _Symbol + "_" + tf + ".csv", InpCsvCommon);
     }
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 50)
      return 0;
   if(BarsCalculated(g_refAtrHandle) <= 0)
      return 0;   // reference ATR not ready yet, retry on next tick

   bool full = (prev_calculated == 0 || !g_built);
   if(full)
     {
      g_eng.Reset();
      g_eng.journal = false;
      g_draw.DeleteAll();
      g_refStart = 0; g_refEnd = 0;
      ClearBuffers(0, rates_total - 1);
      datetime from = time[rates_total - 1] - (datetime)((long)InpLookbackDays * 86400);
      int start = 0;
      while(start < rates_total - 1 && time[start] < from)
         start++;
      g_lastIdx = start - 1;
     }

   int lastClosed = rates_total - 2;
   int daysBefore = g_eng.dayCount;
   bool processed = false;
   for(int i = g_lastIdx + 1; i <= lastClosed; i++)
     {
      g_eng.OnBar(time[i], open[i], high[i], low[i], close[i], RefAtr(time[i]));
      WriteBuffers(i);
      processed = true;
     }
   if(lastClosed > g_lastIdx)
      g_lastIdx = lastClosed;
   ClearBuffers(rates_total - 1, rates_total - 1);   // forming bar: nothing evaluated yet

   if(full)
     {
      int first = MathMax(0, g_eng.dayCount - InpDrawDays);
      for(int d = first; d < g_eng.dayCount; d++)
         g_draw.DrawDay(g_eng, d, WithLabels(d));
      RefreshStats();
      g_built = true;
      g_eng.journal = InpJournal;
     }
   else if(processed)
     {
      if(g_eng.dayCount != daysBefore)
        {
         // new story day: finish the previous one, drop days leaving the window
         int firstDrawn = MathMax(0, g_eng.dayCount - InpDrawDays);
         for(int d = MathMax(firstDrawn, MathMin(daysBefore - 1, daysBefore - InpLabelDays)); d < g_eng.dayCount - 1; d++)
            g_draw.DrawDay(g_eng, d, WithLabels(d));   // labels move to the newest days
         for(int d = MathMax(0, daysBefore - InpDrawDays); d < firstDrawn; d++)
            g_draw.DeleteDay(g_eng.days[d].dayKey);
         RefreshStats();
        }
      g_draw.DrawDay(g_eng, g_eng.dayCount - 1, WithLabels(g_eng.dayCount - 1));
     }

   if(full || processed)
     {
      g_draw.Layout();
      g_draw.DrawPanel(g_eng, g_statLines);
      ChartRedraw();
     }
   return rates_total;
  }
//+------------------------------------------------------------------+

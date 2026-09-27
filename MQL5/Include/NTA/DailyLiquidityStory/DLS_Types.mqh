//+------------------------------------------------------------------+
//|                                                 DLS_Types.mqh    |
//|  NTA Daily Liquidity Story - shared enums, structs and helpers   |
//|                                                                  |
//|  Asia -> London -> New York liquidity sequence state machine.    |
//|  This file has no chart dependencies so it can be reused by an   |
//|  indicator, an EA or a backtest script.                          |
//+------------------------------------------------------------------+
#ifndef NTA_DLS_TYPES_MQH
#define NTA_DLS_TYPES_MQH

#define DLS_LEVEL_SLOTS 8
#define DLS_LEG_BEAR    0
#define DLS_LEG_BULL    1

//--- Daily story state machine (section 20 of the spec).
//    Transient states (ASIA_LOCKED, LONDON_LOCKED, NY_LIQUIDITY_SWEPT,
//    DISPLACEMENT_CONFIRMED, MSS_CONFIRMED, FVG_CONFIRMED) are reported
//    on the bar where the transition happens, the next bar moves to the
//    corresponding WAIT_* state.
enum ENUM_DLS_STATE
  {
   DLS_DAY_START = 0,
   DLS_ASIA_BUILDING,
   DLS_ASIA_LOCKED,
   DLS_WAIT_LONDON,
   DLS_LONDON_MONITORING_ASIA,
   DLS_LONDON_BUILDING_LIQUIDITY,
   DLS_LONDON_LOCKED,
   DLS_WAIT_NEW_YORK,
   DLS_NY_MONITORING_LIQUIDITY,
   DLS_NY_LIQUIDITY_SWEPT,
   DLS_WAIT_DISPLACEMENT,
   DLS_DISPLACEMENT_CONFIRMED,
   DLS_WAIT_MSS,
   DLS_MSS_CONFIRMED,
   DLS_WAIT_FVG,
   DLS_FVG_CONFIRMED,
   DLS_WAIT_RETRACE,
   DLS_STORY_COMPLETE,
   DLS_STORY_INVALIDATED,
   DLS_NY_BOTH_SIDES_TAKEN,     // both sides taken, waiting for structure
   DLS_NY_NO_REVERSAL,          // liquidity swept, no reversal confirmation
   DLS_NY_NO_SWEEP,             // NY window closed without sweeping a target
   DLS_NO_STORY_FVG,            // MSS confirmed but no FVG in time
   DLS_NO_RETRACE               // FVG found but price never retraced before cutoff
  };

//--- Session attribution of an event (which session "did" it).
enum ENUM_DLS_SESSION
  {
   DLS_SES_NONE = 0,
   DLS_SES_ASIA,
   DLS_SES_PRE_LONDON,
   DLS_SES_LONDON,
   DLS_SES_PRE_NY,
   DLS_SES_NY,
   DLS_SES_POST_NY
  };

//--- Liquidity levels tracked each day (fixed slots).
enum ENUM_DLS_LEVEL_KIND
  {
   DLS_LV_ASIA_HIGH = 0,
   DLS_LV_ASIA_LOW,
   DLS_LV_LONDON_HIGH,
   DLS_LV_LONDON_LOW,
   DLS_LV_PDH,
   DLS_LV_PDL,
   DLS_LV_SWING_HIGH,
   DLS_LV_SWING_LOW
  };

//--- Sweep vs breakout classification of a level (section 4).
enum ENUM_DLS_LEVEL_STATUS
  {
   DLS_LVS_ACTIVE = 0,     // untouched liquidity
   DLS_LVS_PENDING,        // closed beyond, neither reclaimed nor accepted yet
   DLS_LVS_WICK_SWEPT,     // wick beyond, candle closed back inside
   DLS_LVS_RECLAIMED,      // closed beyond, then closed back inside
   DLS_LVS_ACCEPTED        // N consecutive closes beyond: broken / accepted
  };

enum ENUM_DLS_RANGE_CLASS
  {
   DLS_RANGE_UNKNOWN = 0,
   DLS_RANGE_NARROW,
   DLS_RANGE_NORMAL,
   DLS_RANGE_WIDE
  };

//--- London raid of Asia liquidity (cases A-D, section 3).
enum ENUM_DLS_ASIA_RAID
  {
   DLS_RAID_PENDING = 0,
   DLS_ASIA_HIGH_SWEPT,
   DLS_ASIA_LOW_SWEPT,
   DLS_ASIA_BOTH_SWEPT,
   DLS_ASIA_NOT_SWEPT
  };

//--- What London did with Asia (section 6).
enum ENUM_DLS_LONDON_STORY
  {
   DLS_LS_PENDING = 0,
   DLS_LS_SWEPT_ASIA_HIGH,
   DLS_LS_SWEPT_ASIA_LOW,
   DLS_LS_SWEPT_BOTH,
   DLS_LS_BROKE_ASIA_HIGH,
   DLS_LS_BROKE_ASIA_LOW,
   DLS_LS_INSIDE_ASIA,
   DLS_LS_NO_CLEAR_EVENT
  };

//--- Pre-commit reversal leg (one per direction, so both-sides sweeps
//    never force a direction from the first sweep - section 18).
enum ENUM_DLS_LEG_STAGE
  {
   DLS_LEG_IDLE = 0,
   DLS_LEG_WAIT_DISP,
   DLS_LEG_WAIT_MSS,
   DLS_LEG_COMMITTED,
   DLS_LEG_FAILED,
   DLS_LEG_CANCELLED
  };

enum ENUM_DLS_LEG_FAIL
  {
   DLS_FAIL_NONE = 0,
   DLS_FAIL_NO_DISPLACEMENT,
   DLS_FAIL_NO_MSS,
   DLS_FAIL_ACCEPTANCE,      // price accepted beyond the swept level
   DLS_FAIL_STRUCTURE,       // closed beyond the sweep extreme
   DLS_FAIL_CUTOFF           // NY development cutoff reached
  };

//--- Committed story stage (after MSS).
enum ENUM_DLS_STORY_STAGE
  {
   DLS_ST_NONE = 0,
   DLS_ST_WAIT_FVG,
   DLS_ST_WAIT_RETRACE,
   DLS_ST_COMPLETE,
   DLS_ST_INVALIDATED,
   DLS_ST_NO_FVG,
   DLS_ST_NO_RETRACE
  };

enum ENUM_DLS_EVENT
  {
   DLS_EV_ASIA_LOCKED = 0,
   DLS_EV_LONDON_LOCKED,
   DLS_EV_LEVEL_TAKEN,        // detail = level status right after the take
   DLS_EV_LEVEL_RECLAIMED,
   DLS_EV_LEVEL_ACCEPTED,
   DLS_EV_NY_SWEEP,
   DLS_EV_BOTH_SIDES,
   DLS_EV_DISPLACEMENT,
   DLS_EV_MSS,
   DLS_EV_STORY_FVG,
   DLS_EV_RETRACE,
   DLS_EV_LEG_FAILED,         // detail = ENUM_DLS_LEG_FAIL
   DLS_EV_INVALIDATED,
   DLS_EV_STORY_STALLED       // detail = ENUM_DLS_STORY_STAGE (NO_FVG / NO_RETRACE)
  };

//--- Displacement qualification mode (section 11).
enum ENUM_DLS_DISP_MODE
  {
   DLS_DISP_ATR = 0,          // Body >= ATR x factor
   DLS_DISP_BODY,             // Body >= AverageBody x multiplier
   DLS_DISP_BOTH,             // both conditions
   DLS_DISP_EITHER            // any of the two
  };

enum ENUM_DLS_RETRACE_LEVEL
  {
   DLS_RT_PROXIMAL = 0,       // FVG proximal edge
   DLS_RT_CE,                 // Consequent Encroachment (50%)
   DLS_RT_DISTAL              // FVG distal edge
  };

enum ENUM_DLS_BUFFER_MODE
  {
   DLS_BUF_PRICE = 0,         // SweepBuffer in price units
   DLS_BUF_ATR                // SweepBuffer as a fraction of chart ATR
  };

//+------------------------------------------------------------------+
//| Settings (filled from indicator/EA inputs)                        |
//+------------------------------------------------------------------+
struct SDlsSettings
  {
   int               serverToNyHours;   // NY time = server time + this
   int               dayStartMin;       // NY minute of the story-day start
   // windows, NY clock minutes-of-day [start, end)
   int               asiaStart, asiaEnd;
   int               londonStart, londonEnd;
   int               nyStart, nyEnd;    // NY liquidity (sweep) window
   int               nyCutoff;          // last minute for development
   int               evalEnd;           // MFE/MAE evaluation end
   bool              sbAmOn, sbPmOn, sbLonOn;
   int               sbAmStart, sbAmEnd, sbPmStart, sbPmEnd, sbLonStart, sbLonEnd;
   // sweep
   int               bufferMode;
   double            bufferValue;
   int               acceptBars;
   // asia range
   double            narrowRatio, wideRatio;
   // displacement
   int               atrPeriod;
   int               dispMode;
   double            dispAtrFactor;
   int               avgBodyPeriod;
   double            bodyMultiplier;
   int               dispMaxBars;
   // structure
   int               swingStrength;
   int               mssSwingLookback;
   int               mssMaxBars;
   // fvg
   double            fvgMinAtr;
   int               fvgMaxBars;
   bool              fvgAfterMssOnly;
   int               retraceLevel;
  };

//+------------------------------------------------------------------+
//| A liquidity level with its sweep / breakout life cycle            |
//+------------------------------------------------------------------+
struct SDlsLevel
  {
   bool              valid;
   bool              isHigh;
   bool              monitoring;
   bool              nyTarget;        // was an active target when NY opened
   double            price;
   datetime          originTime;      // bar that printed the level
   datetime          lockTime;        // when the level became fixed
   int               status;          // ENUM_DLS_LEVEL_STATUS
   int               takenBy;         // ENUM_DLS_SESSION
   datetime          takenTime;
   double            extreme;         // furthest price beyond the level
   datetime          resolvedTime;    // reclaim / acceptance time
   int               closesBeyond;
  };

//+------------------------------------------------------------------+
//| Reversal leg: sweep -> displacement -> MSS                        |
//+------------------------------------------------------------------+
struct SDlsLeg
  {
   int               dir;             // -1 bearish (after BSL sweep), +1 bullish
   int               stage;           // ENUM_DLS_LEG_STAGE
   int               fail;            // ENUM_DLS_LEG_FAIL
   datetime          failTime;
   int               levelKind;       // last swept level on this side
   double            levelPrice;
   int               sweptMask;       // bit mask of level kinds swept on this side
   int               sweepCount;
   datetime          sweepTime;
   double            sweepExtreme;
   int               barsSinceSweep;
   datetime          dispTime;
   double            dispOpen, dispClose, dispBody, dispAtr;
   int               barsSinceDisp;
   datetime          mssSwingTime;
   double            mssLevel;
   datetime          mssTime;
   bool              fvgFound;
   datetime          fvgTime;         // middle candle
   datetime          fvgFormTime;     // third candle (gap confirmed on its close)
   double            fvgTop, fvgBottom;
  };

//+------------------------------------------------------------------+
//| One trading day story                                             |
//+------------------------------------------------------------------+
struct SDlsDay
  {
   int               dayKey;
   datetime          firstBarTime;
   datetime          lastBarTime;
   bool              finalized;
   int               state;            // ENUM_DLS_STATE
   // day extremes (for next day PDH/PDL)
   double            dayHigh, dayLow;
   double            preNyHigh, preNyLow;
   // ASIA
   bool              asiaStarted, asiaLocked;
   datetime          asiaStartTime, asiaEndTime;
   double            asiaHigh, asiaLow;
   datetime          asiaHighTime, asiaLowTime;
   double            asiaRefAtr, asiaRatio;
   int               asiaClass;        // ENUM_DLS_RANGE_CLASS
   // LONDON
   bool              lonStarted, lonLocked;
   datetime          lonStartTime, lonEndTime;
   double            lonHigh, lonLow;
   datetime          lonHighTime, lonLowTime;
   int               raid;             // ENUM_DLS_ASIA_RAID
   int               londonStory;      // ENUM_DLS_LONDON_STORY
   int               londonFirstSide;  // +1 Asia high taken first, -1 low first
   // levels
   SDlsLevel         lv[DLS_LEVEL_SLOTS];
   // NEW YORK
   bool              nyStarted, nyWindowClosed, nyCutoffDone, evalDone;
   datetime          nyStartTime;
   SDlsLeg           leg[2];
   bool              bothSidesActive;
   bool              nyTookBsl, nyTookSsl;
   // committed story
   bool              committed;
   SDlsLeg           story;
   int               storyStage;       // ENUM_DLS_STORY_STAGE
   datetime          fvgConfirmTime;
   int               barsWaitFvg;
   datetime          retraceTime;
   double            retracePrice;
   datetime          invalidTime;
   double            mfe, mae, storyAtr;
   // silver bullet tags
   bool              sbSweep, sbDisp, sbMss, sbFvg;
   // funnel flags for statistics
   bool              fNySweep, fDisp, fMss, fFvg, fRetrace, fComplete, fInvalid, fNoReversal;
   bool              fModelMatch;      // model 1 / model 2 textbook sequence
   bool              fOppositeLondonSwept;
   int               transient;        // -1 or a transient ENUM_DLS_STATE for this bar
  };

struct SDlsEvent
  {
   int               day;              // index into engine days[]
   datetime          time;
   double            price;
   int               type;             // ENUM_DLS_EVENT
   int               dir;
   int               levelKind;
   int               session;
   int               detail;
  };

struct SDlsFvg
  {
   int               day;
   int               dir;              // +1 bullish, -1 bearish
   datetime          time;             // middle candle
   datetime          formTime;         // third candle
   double            top, bottom;
   bool              story;
  };

struct SDlsSwing
  {
   datetime          time;
   datetime          confirmTime;
   double            price;
   bool              isHigh;
   bool              taken;
  };

//+------------------------------------------------------------------+
//| Text helpers (ASCII source, unicode built at runtime)             |
//+------------------------------------------------------------------+
string DlsCheck()  { return ShortToString(0x2713); }
string DlsCircle() { return ShortToString(0x25CB); }
string DlsCross()  { return ShortToString(0x2717); }
string DlsArrowR() { return ShortToString(0x2192); }
string DlsArrowD() { return ShortToString(0x2193); }
string DlsArrowU() { return ShortToString(0x2191); }

string DlsStateText(const int st)
  {
   switch(st)
     {
      case DLS_DAY_START:                 return "DAY_START";
      case DLS_ASIA_BUILDING:             return "ASIA_BUILDING";
      case DLS_ASIA_LOCKED:               return "ASIA_LOCKED";
      case DLS_WAIT_LONDON:               return "WAIT_LONDON";
      case DLS_LONDON_MONITORING_ASIA:    return "LONDON_MONITORING_ASIA";
      case DLS_LONDON_BUILDING_LIQUIDITY: return "LONDON_BUILDING_LIQUIDITY";
      case DLS_LONDON_LOCKED:             return "LONDON_LOCKED";
      case DLS_WAIT_NEW_YORK:             return "WAIT_NEW_YORK";
      case DLS_NY_MONITORING_LIQUIDITY:   return "NY_MONITORING_LIQUIDITY";
      case DLS_NY_LIQUIDITY_SWEPT:        return "NY_LIQUIDITY_SWEPT";
      case DLS_WAIT_DISPLACEMENT:         return "WAIT_DISPLACEMENT";
      case DLS_DISPLACEMENT_CONFIRMED:    return "DISPLACEMENT_CONFIRMED";
      case DLS_WAIT_MSS:                  return "WAIT_MSS";
      case DLS_MSS_CONFIRMED:             return "MSS_CONFIRMED";
      case DLS_WAIT_FVG:                  return "WAIT_FVG";
      case DLS_FVG_CONFIRMED:             return "FVG_CONFIRMED";
      case DLS_WAIT_RETRACE:              return "WAIT_RETRACE";
      case DLS_STORY_COMPLETE:            return "STORY_COMPLETE";
      case DLS_STORY_INVALIDATED:         return "STORY_INVALIDATED";
      case DLS_NY_BOTH_SIDES_TAKEN:       return "NY_BOTH_SIDES_TAKEN";
      case DLS_NY_NO_REVERSAL:            return "NY_NO_REVERSAL";
      case DLS_NY_NO_SWEEP:               return "NY_NO_SWEEP";
      case DLS_NO_STORY_FVG:              return "NO_STORY_FVG";
      case DLS_NO_RETRACE:                return "NO_RETRACE";
     }
   return "UNKNOWN";
  }

string DlsSessionText(const int s)
  {
   switch(s)
     {
      case DLS_SES_ASIA:       return "ASIA";
      case DLS_SES_PRE_LONDON: return "PRE-LONDON";
      case DLS_SES_LONDON:     return "LONDON";
      case DLS_SES_PRE_NY:     return "PRE-NY";
      case DLS_SES_NY:         return "NY";
      case DLS_SES_POST_NY:    return "POST-NY";
     }
   return "-";
  }

string DlsLevelName(const int k)
  {
   switch(k)
     {
      case DLS_LV_ASIA_HIGH:   return "Asia H";
      case DLS_LV_ASIA_LOW:    return "Asia L";
      case DLS_LV_LONDON_HIGH: return "London H";
      case DLS_LV_LONDON_LOW:  return "London L";
      case DLS_LV_PDH:         return "PDH";
      case DLS_LV_PDL:         return "PDL";
      case DLS_LV_SWING_HIGH:  return "Swing H";
      case DLS_LV_SWING_LOW:   return "Swing L";
     }
   return "?";
  }

//--- "ASIA BSL", "LONDON SSL", ...
string DlsLiquidityName(const int k)
  {
   switch(k)
     {
      case DLS_LV_ASIA_HIGH:   return "ASIA BSL";
      case DLS_LV_ASIA_LOW:    return "ASIA SSL";
      case DLS_LV_LONDON_HIGH: return "LONDON BSL";
      case DLS_LV_LONDON_LOW:  return "LONDON SSL";
      case DLS_LV_PDH:         return "PDH BSL";
      case DLS_LV_PDL:         return "PDL SSL";
      case DLS_LV_SWING_HIGH:  return "SWING BSL";
      case DLS_LV_SWING_LOW:   return "SWING SSL";
     }
   return "?";
  }

string DlsLevelStatusText(const int st)
  {
   switch(st)
     {
      case DLS_LVS_ACTIVE:     return "ACTIVE";
      case DLS_LVS_PENDING:    return "TRADED THROUGH";
      case DLS_LVS_WICK_SWEPT: return "WICK SWEPT";
      case DLS_LVS_RECLAIMED:  return "RECLAIMED";
      case DLS_LVS_ACCEPTED:   return "BROKEN / ACCEPTED";
     }
   return "?";
  }

bool DlsIsSwept(const int st)  { return st == DLS_LVS_WICK_SWEPT || st == DLS_LVS_RECLAIMED; }
bool DlsIsTaken(const int st)  { return st != DLS_LVS_ACTIVE; }

string DlsRangeClassText(const int c)
  {
   switch(c)
     {
      case DLS_RANGE_NARROW: return "NARROW";
      case DLS_RANGE_NORMAL: return "NORMAL";
      case DLS_RANGE_WIDE:   return "WIDE";
     }
   return "N/A";
  }

string DlsRaidText(const int r)
  {
   switch(r)
     {
      case DLS_ASIA_HIGH_SWEPT: return "ASIA_HIGH_SWEPT";
      case DLS_ASIA_LOW_SWEPT:  return "ASIA_LOW_SWEPT";
      case DLS_ASIA_BOTH_SWEPT: return "ASIA_BOTH_SWEPT";
      case DLS_ASIA_NOT_SWEPT:  return "ASIA_NOT_SWEPT";
     }
   return "PENDING";
  }

string DlsLondonStoryText(const int s)
  {
   switch(s)
     {
      case DLS_LS_SWEPT_ASIA_HIGH: return "LONDON_SWEPT_ASIA_HIGH";
      case DLS_LS_SWEPT_ASIA_LOW:  return "LONDON_SWEPT_ASIA_LOW";
      case DLS_LS_SWEPT_BOTH:      return "LONDON_SWEPT_BOTH";
      case DLS_LS_BROKE_ASIA_HIGH: return "LONDON_BROKE_ASIA_HIGH";
      case DLS_LS_BROKE_ASIA_LOW:  return "LONDON_BROKE_ASIA_LOW";
      case DLS_LS_INSIDE_ASIA:     return "LONDON_INSIDE_ASIA";
      case DLS_LS_NO_CLEAR_EVENT:  return "LONDON_NO_CLEAR_EVENT";
     }
   return "PENDING";
  }

//--- Human readable London result line for the panel
string DlsLondonResultText(const int s)
  {
   switch(s)
     {
      case DLS_LS_SWEPT_ASIA_HIGH: return "ASIA BSL RAIDED";
      case DLS_LS_SWEPT_ASIA_LOW:  return "ASIA SSL RAIDED";
      case DLS_LS_SWEPT_BOTH:      return "BOTH SIDES LIQUIDITY TAKEN";
      case DLS_LS_BROKE_ASIA_HIGH: return "ASIA HIGH BROKEN / ACCEPTED";
      case DLS_LS_BROKE_ASIA_LOW:  return "ASIA LOW BROKEN / ACCEPTED";
      case DLS_LS_INSIDE_ASIA:     return "INSIDE ASIA RANGE";
      case DLS_LS_NO_CLEAR_EVENT:  return "NO ASIA LIQUIDITY RAID";
     }
   return "PENDING";
  }

string DlsFailText(const int f)
  {
   switch(f)
     {
      case DLS_FAIL_NO_DISPLACEMENT: return "NO DISPLACEMENT";
      case DLS_FAIL_NO_MSS:          return "NO MSS";
      case DLS_FAIL_ACCEPTANCE:      return "ACCEPTANCE BEYOND LEVEL";
      case DLS_FAIL_STRUCTURE:       return "STRUCTURE CONTINUED";
      case DLS_FAIL_CUTOFF:          return "CUTOFF";
     }
   return "-";
  }

string DlsDirText(const int dir)
  {
   if(dir > 0) return "BULLISH";
   if(dir < 0) return "BEARISH";
   return "-";
  }

//--- "HH:MM" -> minutes of day, -1 on error
int DlsParseHHMM(const string s)
  {
   string parts[];
   if(StringSplit(s, ':', parts) != 2)
      return -1;
   int h = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 24 || m < 0 || m > 59)
      return -1;
   return (h * 60 + m) % 1440;
  }

#endif
//+------------------------------------------------------------------+

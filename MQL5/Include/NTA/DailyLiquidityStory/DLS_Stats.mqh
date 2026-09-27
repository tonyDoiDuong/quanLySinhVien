//+------------------------------------------------------------------+
//|                                                 DLS_Stats.mqh    |
//|  NTA Daily Liquidity Story - sequence statistics + CSV export    |
//|                                                                  |
//|  Purpose: VERIFY the story with data. Nothing here assumes the   |
//|  ICT/SMC sequence has an edge; it only counts what happened.     |
//+------------------------------------------------------------------+
#ifndef NTA_DLS_STATS_MQH
#define NTA_DLS_STATS_MQH

#include "DLS_Engine.mqh"

struct SDlsFunnel
  {
   int               days;          // finalized days with a London lock
   int               lonSweptHigh;  // A
   int               lonSweptLow;   // B
   int               lonSweptBoth;  // C
   int               lonBrokeHigh;
   int               lonBrokeLow;
   int               lonOneSide;    // London swept exactly one Asia side
   int               nyOpposite;    // D
   int               nySweep;       // E base
   int               disp;          // E
   int               mss;           // F
   int               fvg;           // G
   int               retrace;       // H
   int               invalid;
   int               noReversal;
   int               modelMatch;
   int               nyBothSides;
   // MFE / MAE (I, J) in ATR units, split in/out Silver Bullet (L)
   int               nIn, nOut;
   double            mfeIn, maeIn, mfeOut, maeOut;
   int               fvgIn, fvgOut, rtIn, rtOut;
   // Asia range class split
   int               cls[4];
   int               clsSweep[4];
  };

class CDlsStats
  {
public:
   SDlsFunnel        f;

   void              Compute(CDlsEngine &eng)
     {
      ZeroMemory(f);
      for(int i = 0; i < eng.dayCount; i++)
        {
         if(!eng.days[i].finalized || !eng.days[i].lonLocked)
            continue;
         f.days++;
         int ls = eng.days[i].londonStory;
         bool hi = eng.days[i].lv[DLS_LV_ASIA_HIGH].takenBy == DLS_SES_LONDON;
         bool lo = eng.days[i].lv[DLS_LV_ASIA_LOW].takenBy == DLS_SES_LONDON;
         if(ls == DLS_LS_SWEPT_ASIA_HIGH || (ls == DLS_LS_SWEPT_BOTH && hi)) f.lonSweptHigh++;
         if(ls == DLS_LS_SWEPT_ASIA_LOW  || (ls == DLS_LS_SWEPT_BOTH && lo)) f.lonSweptLow++;
         if(ls == DLS_LS_SWEPT_BOTH)      f.lonSweptBoth++;
         if(ls == DLS_LS_BROKE_ASIA_HIGH) f.lonBrokeHigh++;
         if(ls == DLS_LS_BROKE_ASIA_LOW)  f.lonBrokeLow++;
         if(ls == DLS_LS_SWEPT_ASIA_HIGH || ls == DLS_LS_SWEPT_ASIA_LOW)
           {
            f.lonOneSide++;
            if(eng.days[i].fOppositeLondonSwept) f.nyOpposite++;
           }
         int c = eng.days[i].asiaClass;
         if(c >= 0 && c < 4)
           {
            f.cls[c]++;
            if(ls == DLS_LS_SWEPT_ASIA_HIGH || ls == DLS_LS_SWEPT_ASIA_LOW || ls == DLS_LS_SWEPT_BOTH)
               f.clsSweep[c]++;
           }
         if(eng.days[i].nyTookBsl && eng.days[i].nyTookSsl) f.nyBothSides++;
         if(eng.days[i].fNySweep)    f.nySweep++;
         if(eng.days[i].fDisp)       f.disp++;
         if(eng.days[i].fMss)        f.mss++;
         if(eng.days[i].fFvg)        f.fvg++;
         if(eng.days[i].fRetrace)    f.retrace++;
         if(eng.days[i].fInvalid)    f.invalid++;
         if(eng.days[i].fNoReversal && !eng.days[i].fMss) f.noReversal++;
         if(eng.days[i].fModelMatch) f.modelMatch++;
         // Silver Bullet tag: MSS or story FVG inside an enabled window
         bool sb = eng.days[i].sbFvg || eng.days[i].sbMss;
         if(eng.days[i].fFvg)
           {
            if(sb) f.fvgIn++; else f.fvgOut++;
            if(eng.days[i].fRetrace)
              {
               if(sb) f.rtIn++; else f.rtOut++;
              }
           }
         if(eng.days[i].fRetrace && eng.days[i].storyAtr > 0)
           {
            double mfe = eng.days[i].mfe / eng.days[i].storyAtr;
            double mae = eng.days[i].mae / eng.days[i].storyAtr;
            if(sb) { f.nIn++;  f.mfeIn += mfe;  f.maeIn += mae; }
            else                  { f.nOut++; f.mfeOut += mfe; f.maeOut += mae; }
           }
        }
     }

   static string     Pct(const int num, const int den)
     {
      if(den <= 0) return StringFormat("%d/0", num);
      return StringFormat("%d/%d %3.0f%%", num, den, 100.0 * num / den);
     }

   static string     Avg(const double sum, const int n)
     {
      if(n <= 0) return "-";
      return DoubleToString(sum / n, 2);
     }

   //--- short lines for the on-chart statistics panel
   int               Lines(string &out[])
     {
      ArrayResize(out, 0);
      Push(out, StringFormat("STATISTICS  (%d days, %s)", f.days, EnumToString((ENUM_TIMEFRAMES)_Period)));
      Push(out, "A London swept Asia H  " + Pct(f.lonSweptHigh, f.days));
      Push(out, "B London swept Asia L  " + Pct(f.lonSweptLow, f.days));
      Push(out, "C London swept both    " + Pct(f.lonSweptBoth, f.days));
      Push(out, "  London broke H / L   " + StringFormat("%d / %d", f.lonBrokeHigh, f.lonBrokeLow));
      Push(out, "D NY swept opp. London " + Pct(f.nyOpposite, f.lonOneSide));
      Push(out, "E Sweep -> Displacement " + Pct(f.disp, f.nySweep));
      Push(out, "F Disp  -> MSS         " + Pct(f.mss, f.disp));
      Push(out, "G MSS   -> FVG         " + Pct(f.fvg, f.mss));
      Push(out, "H FVG   -> Retrace     " + Pct(f.retrace, f.fvg));
      Push(out, "  Invalidated after MSS " + Pct(f.invalid, f.mss));
      Push(out, "  Model 1/2 sequences  " + IntegerToString(f.modelMatch));
      Push(out, "I/J MFE/MAE (ATR)  in SB " + Avg(f.mfeIn, f.nIn) + " / " + Avg(f.maeIn, f.nIn) + " n=" + IntegerToString(f.nIn));
      Push(out, "            outside SB " + Avg(f.mfeOut, f.nOut) + " / " + Avg(f.maeOut, f.nOut) + " n=" + IntegerToString(f.nOut));
      Push(out, "L FVG->Retrace in SB   " + Pct(f.rtIn, f.fvgIn));
      Push(out, "  FVG->Retrace out SB  " + Pct(f.rtOut, f.fvgOut));
      Push(out, "Asia N/No/W swept by Lon " + StringFormat("%s | %s | %s",
            Pct(f.clsSweep[DLS_RANGE_NARROW], f.cls[DLS_RANGE_NARROW]),
            Pct(f.clsSweep[DLS_RANGE_NORMAL], f.cls[DLS_RANGE_NORMAL]),
            Pct(f.clsSweep[DLS_RANGE_WIDE],   f.cls[DLS_RANGE_WIDE])));
      return ArraySize(out);
     }

   //--- one row per finalized day, K = symbol / timeframe columns
   bool              ExportCsv(CDlsEngine &eng, const string fileName, const bool common)
     {
      int flags = FILE_WRITE | FILE_CSV | FILE_ANSI;
      if(common) flags |= FILE_COMMON;
      int h = FileOpen(fileName, flags, ',');
      if(h == INVALID_HANDLE)
        {
         PrintFormat("NTA DLS: cannot write %s (err %d)", fileName, GetLastError());
         return false;
        }
      FileWrite(h, "date", "symbol", "timeframe",
                "asia_high", "asia_low", "asia_range", "asia_ref_atr", "asia_ratio", "asia_class",
                "asia_raid", "london_story", "london_first_side",
                "asia_high_status", "asia_high_by", "asia_low_status", "asia_low_by",
                "london_high", "london_low", "london_high_status", "london_high_by", "london_low_status", "london_low_by",
                "ny_took_bsl", "ny_took_ssl", "ny_opposite_london_swept",
                "story_dir", "story_level", "story_levels_mask",
                "ny_sweep", "displacement", "disp_atr", "mss", "story_fvg", "retrace", "complete",
                "invalidated", "no_reversal", "leg_fail_bear", "leg_fail_bull", "model_match",
                "sb_sweep", "sb_disp", "sb_mss", "sb_fvg",
                "sweep_time", "disp_time", "mss_time", "fvg_time", "retrace_time",
                "entry", "mfe", "mae", "story_atr", "mfe_atr", "mae_atr", "final_state");
      string tf = StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7);
      for(int i = 0; i < eng.dayCount; i++)
        {
         if(!eng.days[i].finalized)
            continue;
         double atr = eng.days[i].storyAtr;
         bool c = eng.days[i].committed;
         FileWrite(h, eng.DayDateText(eng.days[i].dayKey), _Symbol, tf,
                   P(eng.days[i].asiaHigh), P(eng.days[i].asiaLow), P(eng.days[i].asiaHigh - eng.days[i].asiaLow),
                   P(eng.days[i].asiaRefAtr), DoubleToString(eng.days[i].asiaRatio, 3), DlsRangeClassText(eng.days[i].asiaClass),
                   DlsRaidText(eng.days[i].raid), DlsLondonStoryText(eng.days[i].londonStory), eng.days[i].londonFirstSide,
                   LvStatus(eng.days[i].lv[DLS_LV_ASIA_HIGH]), DlsSessionText(eng.days[i].lv[DLS_LV_ASIA_HIGH].takenBy),
                   LvStatus(eng.days[i].lv[DLS_LV_ASIA_LOW]),  DlsSessionText(eng.days[i].lv[DLS_LV_ASIA_LOW].takenBy),
                   P(eng.days[i].lonHigh), P(eng.days[i].lonLow),
                   LvStatus(eng.days[i].lv[DLS_LV_LONDON_HIGH]), DlsSessionText(eng.days[i].lv[DLS_LV_LONDON_HIGH].takenBy),
                   LvStatus(eng.days[i].lv[DLS_LV_LONDON_LOW]),  DlsSessionText(eng.days[i].lv[DLS_LV_LONDON_LOW].takenBy),
                   B(eng.days[i].nyTookBsl), B(eng.days[i].nyTookSsl), B(eng.days[i].fOppositeLondonSwept),
                   c ? DlsDirText(eng.days[i].story.dir) : "-", c ? DlsLevelName(eng.days[i].story.levelKind) : "-",
                   c ? eng.days[i].story.sweptMask : 0,
                   B(eng.days[i].fNySweep), B(eng.days[i].fDisp), c ? DoubleToString(eng.days[i].story.dispAtr, 2) : "",
                   B(eng.days[i].fMss), B(eng.days[i].fFvg), B(eng.days[i].fRetrace), B(eng.days[i].fComplete),
                   B(eng.days[i].fInvalid), B(eng.days[i].fNoReversal),
                   DlsFailText(eng.days[i].leg[DLS_LEG_BEAR].fail), DlsFailText(eng.days[i].leg[DLS_LEG_BULL].fail),
                   B(eng.days[i].fModelMatch),
                   B(eng.days[i].sbSweep), B(eng.days[i].sbDisp), B(eng.days[i].sbMss), B(eng.days[i].sbFvg),
                   T(c ? eng.days[i].story.sweepTime : 0), T(c ? eng.days[i].story.dispTime : 0),
                   T(c ? eng.days[i].story.mssTime : 0), T(eng.days[i].fFvg ? eng.days[i].story.fvgFormTime : 0),
                   T(eng.days[i].retraceTime),
                   eng.days[i].fRetrace ? P(eng.days[i].retracePrice) : "",
                   eng.days[i].fRetrace ? P(eng.days[i].mfe) : "", eng.days[i].fRetrace ? P(eng.days[i].mae) : "",
                   P(atr),
                   (eng.days[i].fRetrace && atr > 0) ? DoubleToString(eng.days[i].mfe / atr, 3) : "",
                   (eng.days[i].fRetrace && atr > 0) ? DoubleToString(eng.days[i].mae / atr, 3) : "",
                   DlsStateText(eng.days[i].state));
        }
      FileClose(h);
      return true;
     }

private:
   static void       Push(string &arr[], const string s)
     {
      int n = ArraySize(arr);
      ArrayResize(arr, n + 1);
      arr[n] = s;
     }
   static string     P(const double v) { return DoubleToString(v, _Digits); }
   static string     B(const bool v)   { return v ? "1" : "0"; }
   static string     T(const datetime t) { return (t > 0) ? TimeToString(t, TIME_DATE | TIME_MINUTES) : ""; }
   static string     LvStatus(const SDlsLevel &v) { return v.valid ? DlsLevelStatusText(v.status) : "-"; }
  };

#endif
//+------------------------------------------------------------------+

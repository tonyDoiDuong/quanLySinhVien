//+------------------------------------------------------------------+
//|                                              DLS_Renderer.mqh    |
//|  NTA Daily Liquidity Story - chart objects, story labels, panel  |
//+------------------------------------------------------------------+
#ifndef NTA_DLS_RENDERER_MQH
#define NTA_DLS_RENDERER_MQH

#include "DLS_Engine.mqh"

struct SDlsStyle
  {
   color             asiaBox, londonBox;
   color             bslColor, sslColor, pdColor, swingColor;
   color             bearColor, bullColor, neutralColor;
   color             normalFvg, storyFvgBear, storyFvgBull;
   color             textColor;
   color             panelBg, panelBorder, panelText, panelHeader, panelOk, panelWait, panelFail, panelMuted;
   int               labelFontSize;
   string            panelFont;
   int               panelFontSize;
   int               panelCorner;
   int               panelX, panelY, panelWidth;
   bool              showPanel, showStats, showLabels, showPath, showNormalFvg, showPdLevels, showSwingTargets;
   int               normalFvgBars;
  };

class CDlsRenderer
  {
private:
   string            m_pfx;
   long              m_chart;
   SDlsStyle         st;
   string            m_txt[];
   color             m_clr[];

public:
                     CDlsRenderer(void) { m_pfx = "NTA_DLS_"; m_chart = 0; }
   void              Init(const SDlsStyle &style, const long chart_id = 0) { st = style; m_chart = chart_id; }
   string            Prefix(void) const { return m_pfx; }
   void              DeleteAll(void) { ObjectsDeleteAll(m_chart, m_pfx); }

   //+---------------------------------------------------------------+
   //| Chart story of one day                                          |
   //+---------------------------------------------------------------+
   void              DrawDay(CDlsEngine &eng, const int i)
     {
      if(i < 0 || i >= eng.dayCount)
         return;
      SDlsDay d = eng.days[i];
      string p = m_pfx + IntegerToString(d.dayKey) + "_";
      datetime cutT = eng.TimeOfStoryMinute(d.dayKey, eng.NyCutoffSm());
      datetime lineEnd = d.lastBarTime + eng.periodSec;
      if(cutT > lineEnd) lineEnd = cutT;

      // ---- ASIA box
      if(d.asiaStarted)
        {
         Rect(p + "ASIA_BOX", d.asiaStartTime, d.asiaHigh, d.asiaEndTime, d.asiaLow, st.asiaBox);
         string cap = "ASIA";
         if(d.asiaLocked)
            cap += "  " + DlsRangeClassText(d.asiaClass) + (d.asiaRefAtr > 0 ? StringFormat(" %.2f ATR", d.asiaRatio) : "");
         else
            cap += "  BUILDING";
         Txt(p + "ASIA_CAP", d.asiaStartTime, d.asiaHigh, cap, st.textColor, ANCHOR_LEFT_LOWER);
        }
      // ---- LONDON box
      if(d.lonStarted)
        {
         Rect(p + "LON_BOX", d.lonStartTime, d.lonHigh, d.lonEndTime, d.lonLow, st.londonBox);
         string cap = "LONDON";
         if(d.lonLocked)
            cap += "  " + DlsLondonResultText(d.londonStory);
         else
            cap += "  BUILDING";
         Txt(p + "LON_CAP", d.lonStartTime, d.lonHigh, cap, st.textColor, ANCHOR_LEFT_LOWER);
        }

      // ---- liquidity levels
      for(int k = 0; k < DLS_LEVEL_SLOTS; k++)
        {
         if(!d.lv[k].valid)
            continue;
         if((k == DLS_LV_PDH || k == DLS_LV_PDL) && !st.showPdLevels)
            continue;
         if((k == DLS_LV_SWING_HIGH || k == DLS_LV_SWING_LOW) && !st.showSwingTargets)
            continue;
         datetime t1 = d.lv[k].lockTime;
         if(k == DLS_LV_ASIA_HIGH || k == DLS_LV_ASIA_LOW)     t1 = d.asiaEndTime;
         if(k == DLS_LV_LONDON_HIGH || k == DLS_LV_LONDON_LOW) t1 = d.lonEndTime;
         if(k == DLS_LV_PDH || k == DLS_LV_PDL)                t1 = d.firstBarTime;
         if(k == DLS_LV_SWING_HIGH || k == DLS_LV_SWING_LOW)   t1 = d.lv[k].originTime;
         datetime t2 = DlsIsTaken(d.lv[k].status) ? d.lv[k].takenTime : lineEnd;
         if(t2 <= t1) t2 = t1 + eng.periodSec;
         color c = LevelColor(k);
         ENUM_LINE_STYLE ls = STYLE_SOLID;
         if(DlsIsSwept(d.lv[k].status))                ls = STYLE_DASH;
         if(d.lv[k].status == DLS_LVS_ACCEPTED ||
            d.lv[k].status == DLS_LVS_PENDING)         ls = STYLE_DOT;
         Seg(p + "LV" + IntegerToString(k), t1, d.lv[k].price, t2, d.lv[k].price, c, ls, 1);
         Txt(p + "LVT" + IntegerToString(k), t1, d.lv[k].price, LevelCaption(d.lv[k], k),
             c, d.lv[k].isHigh ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
        }

      // ---- normal FVGs (context only)
      if(st.showNormalFvg)
        {
         for(int f = eng.fvgCount - 1; f >= 0; f--)
           {
            if(eng.fvgs[f].day < i) break;
            if(eng.fvgs[f].day != i || eng.fvgs[f].story) continue;
            Rect(p + "NF" + IntegerToString((long)eng.fvgs[f].time) + (eng.fvgs[f].dir > 0 ? "U" : "D"),
                 eng.fvgs[f].time, eng.fvgs[f].top, eng.fvgs[f].time + st.normalFvgBars * eng.periodSec, eng.fvgs[f].bottom, st.normalFvg);
           }
        }

      // ---- committed story geometry
      if(d.committed)
        {
         color dc = DirColor(d.story.dir);
         if(d.story.mssLevel > 0 && d.story.mssTime > 0)
           {
            Seg(p + "MSS_LINE", d.story.mssSwingTime, d.story.mssLevel, d.story.mssTime, d.story.mssLevel, dc, STYLE_SOLID, 2);
           }
         if(d.fFvg)
           {
            datetime fe = (d.retraceTime > 0) ? d.retraceTime : lineEnd;
            Rect(p + "STORY_FVG", d.story.fvgTime, d.story.fvgTop, fe, d.story.fvgBottom, d.story.dir < 0 ? st.storyFvgBear : st.storyFvgBull);
            double ce = (d.story.fvgTop + d.story.fvgBottom) * 0.5;
            Seg(p + "STORY_FVG_CE", d.story.fvgTime, ce, fe, ce, dc, STYLE_DOT, 1);
           }
        }

      // ---- story labels from events
      if(st.showLabels)
         for(int e = 0; e < eng.evCount; e++)
            if(eng.events[e].day == i)
               DrawEvent(eng, d, e, p);

      // ---- story path
      if(st.showPath)
         DrawPath(d, p);
     }

   //+---------------------------------------------------------------+
   //| Timeline panel (section 21)                                     |
   //+---------------------------------------------------------------+
   void              DrawPanel(CDlsEngine &eng, string &statLines[])
     {
      ObjectsDeleteAll(m_chart, m_pfx + "PNL_");
      if(!st.showPanel || eng.dayCount == 0)
         return;
      SDlsDay d = eng.days[eng.dayCount - 1];
      ArrayResize(m_txt, 0);
      ArrayResize(m_clr, 0);

      Add("NTA DAILY LIQUIDITY STORY  " + eng.DayDateText(d.dayKey), st.panelHeader);
      Add("", st.panelMuted);
      // ASIA
      string ah = "ASIA";
      if(d.asiaLocked)
         ah += "  [" + DlsRangeClassText(d.asiaClass) + (d.asiaRefAtr > 0 ? StringFormat(" %.2f ATR", d.asiaRatio) : "") + "]";
      else if(d.asiaStarted)
         ah += "  [BUILDING]";
      Add(ah, st.panelHeader);
      if(d.asiaStarted)
        {
         Add(Row("H " + Px(d.asiaHigh), d.asiaLocked ? LvPanel(d.lv[DLS_LV_ASIA_HIGH]) : "BUILDING"), LvColor(d.lv[DLS_LV_ASIA_HIGH], d.asiaLocked));
         Add(Row("L " + Px(d.asiaLow),  d.asiaLocked ? LvPanel(d.lv[DLS_LV_ASIA_LOW])  : "BUILDING"), LvColor(d.lv[DLS_LV_ASIA_LOW], d.asiaLocked));
        }
      else
         Add("  waiting for Asia", st.panelMuted);
      // LONDON
      Add("LONDON", st.panelHeader);
      if(d.lonStarted)
        {
         Add(Row("H " + Px(d.lonHigh), d.lonLocked ? LvPanel(d.lv[DLS_LV_LONDON_HIGH]) : "BUILDING"), LvColor(d.lv[DLS_LV_LONDON_HIGH], d.lonLocked));
         Add(Row("L " + Px(d.lonLow),  d.lonLocked ? LvPanel(d.lv[DLS_LV_LONDON_LOW])  : "BUILDING"), LvColor(d.lv[DLS_LV_LONDON_LOW], d.lonLocked));
         if(d.lonLocked)
            Add("RESULT: " + DlsLondonResultText(d.londonStory), st.panelText);
        }
      else
         Add("  waiting for London", st.panelMuted);
      // NEW YORK
      Add("NEW YORK", st.panelHeader);
      if(d.nyStarted)
        {
         int shown = 0;
         int order[8] = {DLS_LV_LONDON_HIGH, DLS_LV_LONDON_LOW, DLS_LV_ASIA_HIGH, DLS_LV_ASIA_LOW, DLS_LV_PDH, DLS_LV_PDL, DLS_LV_SWING_HIGH, DLS_LV_SWING_LOW};
         for(int n = 0; n < 8; n++)
           {
            int k = order[n];
            if(!d.lv[k].valid || !d.lv[k].nyTarget) continue;
            bool took = d.lv[k].takenBy == DLS_SES_NY;
            string txt = took ? (DlsIsSwept(d.lv[k].status) ? "SWEPT " + DlsCheck() :
                                 d.lv[k].status == DLS_LVS_ACCEPTED ? "BROKEN " + DlsCross() : "TAKEN " + DlsCheck())
                         : "ACTIVE " + DlsCircle();
            Add(Row(DlsLevelName(k) + " " + Px(d.lv[k].price), txt), took ? st.panelOk : st.panelMuted);
            shown++;
           }
         if(shown == 0)
            Add("  no untouched targets", st.panelMuted);
        }
      else
         Add("  waiting for New York", st.panelMuted);

      Add("", st.panelMuted);
      StepRows(d);
      Add("", st.panelMuted);
      // STORY
      Add("STORY", st.panelHeader);
      StoryRows(d);
      Add("", st.panelMuted);
      Add("STATUS", st.panelHeader);
      StatusRows(d);

      if(st.showStats && ArraySize(statLines) > 0)
        {
         Add("", st.panelMuted);
         for(int n = 0; n < ArraySize(statLines); n++)
            Add(statLines[n], n == 0 ? st.panelHeader : st.panelText);
        }
      RenderPanel();
     }

private:
   //--- object primitives ---------------------------------------------
   void              Rect(const string name, const datetime t1, const double p1, const datetime t2, const double p2, const color c)
     {
      if(ObjectFind(m_chart, name) < 0)
        {
         ObjectCreate(m_chart, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
         ObjectSetInteger(m_chart, name, OBJPROP_FILL, true);
         ObjectSetInteger(m_chart, name, OBJPROP_BACK, true);
         ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN, true);
        }
      ObjectSetInteger(m_chart, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(m_chart, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(m_chart, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(m_chart, name, OBJPROP_PRICE, 1, p2);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, c);
     }

   void              Seg(const string name, const datetime t1, const double p1, const datetime t2, const double p2, const color c, const ENUM_LINE_STYLE ls, const int w)
     {
      if(ObjectFind(m_chart, name) < 0)
        {
         ObjectCreate(m_chart, name, OBJ_TREND, 0, t1, p1, t2, p2);
         ObjectSetInteger(m_chart, name, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(m_chart, name, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN, true);
        }
      ObjectSetInteger(m_chart, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(m_chart, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(m_chart, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(m_chart, name, OBJPROP_PRICE, 1, p2);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, c);
      ObjectSetInteger(m_chart, name, OBJPROP_STYLE, ls);
      ObjectSetInteger(m_chart, name, OBJPROP_WIDTH, w);
     }

   void              Txt(const string name, const datetime t, const double price, const string text, const color c, const ENUM_ANCHOR_POINT anchor)
     {
      if(ObjectFind(m_chart, name) < 0)
        {
         ObjectCreate(m_chart, name, OBJ_TEXT, 0, t, price);
         ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN, true);
         ObjectSetString(m_chart, name, OBJPROP_FONT, "Arial");
        }
      ObjectSetInteger(m_chart, name, OBJPROP_TIME, 0, t);
      ObjectSetDouble(m_chart, name, OBJPROP_PRICE, 0, price);
      ObjectSetString(m_chart, name, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, c);
      ObjectSetInteger(m_chart, name, OBJPROP_FONTSIZE, st.labelFontSize);
      ObjectSetInteger(m_chart, name, OBJPROP_ANCHOR, anchor);
     }

   void              Arrow(const string name, const datetime t, const double price, const int code, const color c, const bool above)
     {
      if(ObjectFind(m_chart, name) < 0)
        {
         ObjectCreate(m_chart, name, OBJ_ARROW, 0, t, price);
         ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN, true);
        }
      ObjectSetInteger(m_chart, name, OBJPROP_TIME, 0, t);
      ObjectSetDouble(m_chart, name, OBJPROP_PRICE, 0, price);
      ObjectSetInteger(m_chart, name, OBJPROP_ARROWCODE, code);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, c);
      ObjectSetInteger(m_chart, name, OBJPROP_ANCHOR, above ? ANCHOR_BOTTOM : ANCHOR_TOP);
     }

   //--- styling helpers -----------------------------------------------
   color             LevelColor(const int k) const
     {
      if(k == DLS_LV_PDH || k == DLS_LV_PDL) return st.pdColor;
      if(k == DLS_LV_SWING_HIGH || k == DLS_LV_SWING_LOW) return st.swingColor;
      bool hi = (k == DLS_LV_ASIA_HIGH || k == DLS_LV_LONDON_HIGH);
      return hi ? st.bslColor : st.sslColor;
     }
   color             DirColor(const int dir) const { return dir < 0 ? st.bearColor : (dir > 0 ? st.bullColor : st.neutralColor); }

   string            Px(const double v) const { return DoubleToString(v, _Digits); }

   string            LevelCaption(const SDlsLevel &v, const int k) const
     {
      string s = DlsLiquidityName(k) + " " + Px(v.price);
      if(v.status == DLS_LVS_ACTIVE)
         return s + "  ACTIVE";
      return s + "  " + DlsLevelStatusText(v.status) + " (" + DlsSessionText(v.takenBy) + ")";
     }

   string            LvPanel(const SDlsLevel &v) const
     {
      if(!v.valid) return "-";
      string ses = DlsSessionText(v.takenBy);
      switch(v.status)
        {
         case DLS_LVS_ACTIVE:     return "ACTIVE";
         case DLS_LVS_WICK_SWEPT: return "SWEPT " + ses;
         case DLS_LVS_RECLAIMED:  return "RECLAIMED " + ses;
         case DLS_LVS_PENDING:    return "TRADED " + ses;
         case DLS_LVS_ACCEPTED:   return "BROKEN " + ses;
        }
      return "-";
     }

   color             LvColor(const SDlsLevel &v, const bool locked) const
     {
      if(!locked) return st.panelWait;
      if(v.status == DLS_LVS_ACTIVE) return st.panelText;
      if(DlsIsSwept(v.status)) return st.panelOk;
      return st.panelFail;
     }

   string            Row(const string left, const string right) const
     {
      return StringFormat("%-18s %s", left, right);
     }

   void              Add(const string s, const color c)
     {
      int n = ArraySize(m_txt);
      ArrayResize(m_txt, n + 1);
      ArrayResize(m_clr, n + 1);
      m_txt[n] = s;
      m_clr[n] = c;
     }

   //--- which leg does the panel describe
   bool              FocusLeg(const SDlsDay &d, SDlsLeg &lg) const
     {
      if(d.committed) { lg = d.story; return true; }
      int best = -1, bestRank = -1;
      for(int li = 0; li < 2; li++)
        {
         int r = -1;
         if(d.leg[li].stage == DLS_LEG_WAIT_MSS)  r = 3;
         if(d.leg[li].stage == DLS_LEG_WAIT_DISP) r = 2;
         if(d.leg[li].stage == DLS_LEG_FAILED)    r = 1;
         if(r > bestRank || (r == bestRank && r >= 0 && d.leg[li].sweepTime > d.leg[best].sweepTime))
           {
            bestRank = r;
            best = li;
           }
        }
      if(best < 0 || bestRank < 0) return false;
      lg = d.leg[best];
      return true;
     }

   void              StepRows(const SDlsDay &d)
     {
      SDlsLeg lg;
      ZeroMemory(lg);
      bool has = FocusLeg(d, lg);
      string ok = DlsCheck(), wait = DlsCircle(), no = DlsCross();
      // displacement
      if(!has)
         Add(Row("DISPLACEMENT", "-"), st.panelMuted);
      else if(lg.dispTime > 0)
         Add(Row("DISPLACEMENT", DlsDirText(lg.dir) + " " + ok), st.panelOk);
      else if(lg.stage == DLS_LEG_WAIT_DISP)
         Add(Row("DISPLACEMENT", "WAITING " + DlsDirText(lg.dir) + " " + wait), st.panelWait);
      else
         Add(Row("DISPLACEMENT", "NONE " + no), st.panelFail);
      // MSS
      if(d.committed)
         Add(Row("MSS", DlsDirText(lg.dir) + " " + ok), st.panelOk);
      else if(has && lg.stage == DLS_LEG_WAIT_MSS)
         Add(Row("MSS", "WAITING " + wait), st.panelWait);
      else if(has && lg.stage == DLS_LEG_FAILED && lg.dispTime > 0)
         Add(Row("MSS", "NONE " + no), st.panelFail);
      else
         Add(Row("MSS", "-"), st.panelMuted);
      // FVG
      if(!d.committed)
         Add(Row("FVG", "-"), st.panelMuted);
      else if(d.storyStage == DLS_ST_WAIT_FVG)
         Add(Row("FVG", "WAITING " + wait), st.panelWait);
      else if(d.fFvg)
         Add(Row("FVG", "FOUND " + ok), st.panelOk);
      else
         Add(Row("FVG", "NONE " + no), st.panelFail);
      // RETRACE
      if(!d.fFvg)
         Add(Row("RETRACE", "-"), st.panelMuted);
      else if(d.storyStage == DLS_ST_WAIT_RETRACE)
         Add(Row("RETRACE", "WAITING " + wait), st.panelWait);
      else if(d.fRetrace)
         Add(Row("RETRACE", "RETRACED " + ok), st.panelOk);
      else
         Add(Row("RETRACE", "NONE " + no), st.panelFail);
      // Silver Bullet tag (information only)
      if(d.committed)
        {
         bool sb = d.sbMss || d.sbFvg;
         Add(Row("SILVER BULLET", sb ? "WINDOW " + ok : "OUTSIDE"), sb ? st.panelOk : st.panelMuted);
        }
     }

   void              StoryRows(const SDlsDay &d)
     {
      string ar = DlsArrowR();
      if(!d.lonLocked && !d.lonStarted)
         Add("  -", st.panelMuted);
      else
        {
         bool hi = d.lv[DLS_LV_ASIA_HIGH].takenBy == DLS_SES_LONDON;
         bool lo = d.lv[DLS_LV_ASIA_LOW].takenBy == DLS_SES_LONDON;
         if(hi && lo)  Add("ASIA BSL + SSL " + ar + " LONDON", st.panelText);
         else if(hi)   Add((DlsIsSwept(d.lv[DLS_LV_ASIA_HIGH].status) ? "ASIA BSL " : "ASIA H BROKEN ") + ar + " LONDON", st.panelText);
         else if(lo)   Add((DlsIsSwept(d.lv[DLS_LV_ASIA_LOW].status)  ? "ASIA SSL " : "ASIA L BROKEN ") + ar + " LONDON", st.panelText);
         else          Add("ASIA LIQUIDITY NOT RAIDED BY LONDON", st.panelMuted);
        }
      SDlsLeg lg;
      ZeroMemory(lg);
      if(FocusLeg(d, lg))
        {
         Add(DlsLiquidityName(lg.levelKind) + " " + ar + " NEW YORK", st.panelText);
         if(d.committed)
           {
            string a = lg.dir < 0 ? DlsArrowD() : DlsArrowU();
            string s = "MSS " + a;
            if(d.fFvg) s += " " + ar + " FVG " + a;
            if(d.fRetrace) s += " " + ar + " RETRACE";
            Add(s, DirColor(lg.dir));
           }
        }
      else if(d.nyStarted)
         Add("NY: no liquidity swept yet", st.panelMuted);
     }

   void              StatusRows(const SDlsDay &d)
     {
      string dir = d.committed ? DlsDirText(d.story.dir) : "";
      string s = "";
      color c = st.panelText;
      switch(d.state)
        {
         case DLS_DAY_START:                 s = "WAITING FOR ASIA"; break;
         case DLS_ASIA_BUILDING:             s = "ASIA BUILDING LIQUIDITY"; break;
         case DLS_ASIA_LOCKED:
         case DLS_WAIT_LONDON:               s = "ASIA LIQUIDITY CREATED"; break;
         case DLS_LONDON_MONITORING_ASIA:    s = "LONDON MONITORING ASIA LIQUIDITY"; break;
         case DLS_LONDON_BUILDING_LIQUIDITY: s = "LONDON RAIDED ASIA - BUILDING LIQUIDITY"; break;
         case DLS_LONDON_LOCKED:
         case DLS_WAIT_NEW_YORK:             s = "LONDON LIQUIDITY LOCKED - WAIT NEW YORK"; break;
         case DLS_NY_MONITORING_LIQUIDITY:   s = "NY MONITORING LIQUIDITY"; break;
         case DLS_NY_LIQUIDITY_SWEPT:
         case DLS_WAIT_DISPLACEMENT:         s = "LIQUIDITY SWEPT - WAIT DISPLACEMENT"; c = st.panelWait; break;
         case DLS_DISPLACEMENT_CONFIRMED:
         case DLS_WAIT_MSS:                  s = "DISPLACEMENT - WAIT MSS"; c = st.panelWait; break;
         case DLS_MSS_CONFIRMED:
         case DLS_WAIT_FVG:
         case DLS_FVG_CONFIRMED:
         case DLS_WAIT_RETRACE:              s = "NY " + dir + " STORY DEVELOPING"; c = DirColor(d.story.dir); break;
         case DLS_STORY_COMPLETE:            s = "NY " + dir + " STORY"; c = DirColor(d.story.dir); break;
         case DLS_STORY_INVALIDATED:         s = "STORY INVALIDATED"; c = st.panelFail; break;
         case DLS_NY_BOTH_SIDES_TAKEN:       s = "BOTH SIDES LIQUIDITY TAKEN"; c = st.panelWait; break;
         case DLS_NY_NO_REVERSAL:            s = "LIQUIDITY SWEPT"; c = st.panelFail; break;
         case DLS_NY_NO_SWEEP:               s = "NY: NO LIQUIDITY SWEEP"; c = st.panelMuted; break;
         case DLS_NO_STORY_FVG:              s = "MSS CONFIRMED - NO STORY FVG"; c = st.panelFail; break;
         case DLS_NO_RETRACE:                s = "STORY FVG NOT RETRACED"; c = st.panelMuted; break;
        }
      Add(s, c);
      if(d.state == DLS_NY_BOTH_SIDES_TAKEN)
         Add("WAIT FOR STRUCTURE", st.panelWait);
      if(d.state == DLS_NY_NO_REVERSAL)
         Add("NO REVERSAL CONFIRMATION", st.panelFail);
      if(d.state == DLS_STORY_COMPLETE)
         Add("STORY CONDITIONS COMPLETE", st.panelOk);
      if(d.fModelMatch)
         Add(d.story.dir < 0 ? "MODEL 1: NY BEARISH REVERSAL SEQUENCE" : "MODEL 2: NY BULLISH REVERSAL SEQUENCE", DirColor(d.story.dir));
      if(d.committed && (d.sbMss || d.sbFvg) && d.fFvg)
         Add("SILVER BULLET CONDITIONS PRESENT", st.panelOk);
      Add("[" + DlsStateText(d.state) + "]", st.panelMuted);
     }

   void              RenderPanel(void)
     {
      int n = ArraySize(m_txt);
      int lh = (int)MathRound(st.panelFontSize * 1.75);
      int h = n * lh + 12;
      string bg = m_pfx + "PNL_BG";
      // Rectangle labels keep their top-left anchor in every corner, so
      // right / lower corners measure the distance to that anchor.
      bool right = (st.panelCorner == CORNER_RIGHT_UPPER || st.panelCorner == CORNER_RIGHT_LOWER);
      bool lower = (st.panelCorner == CORNER_LEFT_LOWER || st.panelCorner == CORNER_RIGHT_LOWER);
      int bx = right ? st.panelX + st.panelWidth : st.panelX;
      int by = lower ? st.panelY + h : st.panelY;
      ObjectCreate(m_chart, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(m_chart, bg, OBJPROP_CORNER, st.panelCorner);
      ObjectSetInteger(m_chart, bg, OBJPROP_XDISTANCE, bx);
      ObjectSetInteger(m_chart, bg, OBJPROP_YDISTANCE, by);
      ObjectSetInteger(m_chart, bg, OBJPROP_XSIZE, st.panelWidth);
      ObjectSetInteger(m_chart, bg, OBJPROP_YSIZE, h);
      ObjectSetInteger(m_chart, bg, OBJPROP_BGCOLOR, st.panelBg);
      ObjectSetInteger(m_chart, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chart, bg, OBJPROP_COLOR, st.panelBorder);
      ObjectSetInteger(m_chart, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart, bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(m_chart, bg, OBJPROP_BACK, false);

      for(int i = 0; i < n; i++)
        {
         string nm = m_pfx + "PNL_L" + IntegerToString(i);
         ObjectCreate(m_chart, nm, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chart, nm, OBJPROP_CORNER, st.panelCorner);
         ObjectSetInteger(m_chart, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
         ObjectSetInteger(m_chart, nm, OBJPROP_XDISTANCE, right ? bx - 8 : bx + 8);
         ObjectSetInteger(m_chart, nm, OBJPROP_YDISTANCE, lower ? by - 6 - i * lh : by + 6 + i * lh);
         ObjectSetString(m_chart, nm, OBJPROP_TEXT, m_txt[i] == "" ? " " : m_txt[i]);
         ObjectSetString(m_chart, nm, OBJPROP_FONT, st.panelFont);
         ObjectSetInteger(m_chart, nm, OBJPROP_FONTSIZE, st.panelFontSize);
         ObjectSetInteger(m_chart, nm, OBJPROP_COLOR, m_clr[i]);
         ObjectSetInteger(m_chart, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, nm, OBJPROP_HIDDEN, true);
        }
     }

   //--- event labels (section 22) ---------------------------------------
   void              DrawEvent(CDlsEngine &eng, const SDlsDay &d, const int e, const string p)
     {
      SDlsEvent ev = eng.events[e];
      string nm = p + "EV" + IntegerToString(e);
      bool high = (ev.levelKind == DLS_LV_ASIA_HIGH || ev.levelKind == DLS_LV_LONDON_HIGH ||
                   ev.levelKind == DLS_LV_PDH || ev.levelKind == DLS_LV_SWING_HIGH);
      string liq = DlsLiquidityName(ev.levelKind);
      switch(ev.type)
        {
         case DLS_EV_LEVEL_TAKEN:
           {
            if(ev.session == DLS_SES_NY && d.lv[ev.levelKind].nyTarget)
               return;   // NY targets get the NY SWEEP label instead
            string what = (ev.detail == DLS_LVS_WICK_SWEPT) ? "SWEEP" : (ev.detail == DLS_LVS_ACCEPTED ? "BREAK" : "RAID");
            Txt(nm, ev.time, ev.price, liq + " " + what + " - " + DlsSessionText(ev.session), LevelColor(ev.levelKind),
                high ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
            break;
           }
         case DLS_EV_LEVEL_RECLAIMED:
            Txt(nm, ev.time, ev.price, liq + " RECLAIMED", LevelColor(ev.levelKind), high ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
            break;
         case DLS_EV_LEVEL_ACCEPTED:
            Txt(nm, ev.time, ev.price, liq + " BROKEN / ACCEPTED", LevelColor(ev.levelKind), high ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
            break;
         case DLS_EV_NY_SWEEP:
            Arrow(nm + "A", ev.time, ev.price, high ? 234 : 233, DirColor(ev.dir), high);
            Txt(nm, ev.time, ev.price, "NY SWEEP " + liq, DirColor(ev.dir), high ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
            break;
         case DLS_EV_BOTH_SIDES:
            Txt(nm, ev.time, ev.price, "BOTH SIDES TAKEN - WAIT FOR STRUCTURE", st.neutralColor, ANCHOR_LEFT_UPPER);
            break;
         case DLS_EV_DISPLACEMENT:
            Txt(nm, ev.time, ev.price, (ev.dir < 0 ? "Bearish" : "Bullish") + string(" Displacement"), DirColor(ev.dir),
                ev.dir < 0 ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER);
            break;
         case DLS_EV_MSS:
            Txt(nm, ev.time, ev.price, "MSS " + (ev.dir < 0 ? DlsArrowD() : DlsArrowU()), DirColor(ev.dir),
                ev.dir < 0 ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
            break;
         case DLS_EV_STORY_FVG:
            Txt(nm, ev.time, ev.price, "STORY FVG" + ((d.sbFvg || d.sbMss) ? "  [SILVER BULLET]" : ""), DirColor(ev.dir), ANCHOR_RIGHT);
            break;
         case DLS_EV_RETRACE:
            Arrow(nm + "A", ev.time, ev.price, 159, DirColor(ev.dir), ev.dir < 0);
            Txt(nm, ev.time, ev.price, "RETRACE", DirColor(ev.dir), ev.dir < 0 ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
            break;
         case DLS_EV_LEG_FAILED:
            Txt(nm, ev.time, ev.price, "NO REVERSAL CONFIRMATION (" + DlsFailText(ev.detail) + ")", st.neutralColor,
                ev.dir < 0 ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
            break;
         case DLS_EV_INVALIDATED:
            Txt(nm, ev.time, ev.price, "STORY INVALIDATED", st.neutralColor, ev.dir < 0 ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
            break;
         case DLS_EV_STORY_STALLED:
            Txt(nm, ev.time, ev.price, ev.detail == DLS_ST_NO_FVG ? "NO STORY FVG" : "NO RETRACE", st.neutralColor, ANCHOR_LEFT);
            break;
        }
     }

   void              DrawPath(const SDlsDay &d, const string p)
     {
      datetime pt[];
      double pp[];
      // London raid of Asia
      int firstK = -1;
      if(d.londonFirstSide > 0)      firstK = DLS_LV_ASIA_HIGH;
      else if(d.londonFirstSide < 0) firstK = DLS_LV_ASIA_LOW;
      if(firstK >= 0 && d.asiaLocked)
        {
         AddPt(pt, pp, d.asiaEndTime, (d.asiaHigh + d.asiaLow) * 0.5);
         AddPt(pt, pp, d.lv[firstK].takenTime, d.lv[firstK].price);
         // London then builds the opposite extreme
         if(d.lonLocked)
           {
            if(firstK == DLS_LV_ASIA_LOW) AddPt(pt, pp, d.lonHighTime, d.lonHigh);
            else                          AddPt(pt, pp, d.lonLowTime, d.lonLow);
           }
        }
      SDlsLeg lg;
      ZeroMemory(lg);
      if(FocusLeg(d, lg))
        {
         AddPt(pt, pp, lg.sweepTime, lg.levelPrice);
         if(lg.dispTime > 0) AddPt(pt, pp, lg.dispTime, lg.dispClose);
         if(d.committed)
           {
            AddPt(pt, pp, lg.mssTime, lg.mssLevel);
            if(d.fFvg)     AddPt(pt, pp, lg.fvgFormTime, (lg.fvgTop + lg.fvgBottom) * 0.5);
            if(d.fRetrace) AddPt(pt, pp, d.retraceTime, d.retracePrice);
           }
        }
      for(int i = 1; i < ArraySize(pt); i++)
        {
         if(pt[i] < pt[i - 1]) continue;
         Seg(p + "PATH" + IntegerToString(i), pt[i - 1], pp[i - 1], pt[i], pp[i], st.neutralColor, STYLE_DOT, 1);
        }
     }

   void              AddPt(datetime &t[], double &p[], const datetime tt, const double pp)
     {
      if(tt <= 0) return;
      int n = ArraySize(t);
      ArrayResize(t, n + 1);
      ArrayResize(p, n + 1);
      t[n] = tt;
      p[n] = pp;
     }
  };

#endif
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                DLS_Engine.mqh    |
//|  NTA Daily Liquidity Story - bar driven state machine            |
//|                                                                  |
//|  ASIA creates liquidity -> LONDON raids Asia and creates new     |
//|  liquidity -> NEW YORK sweeps liquidity -> displacement -> MSS   |
//|  -> FVG -> retrace.                                              |
//|                                                                  |
//|  Rules:                                                          |
//|   * Only CLOSED bars are fed to OnBar(): nothing repaints.       |
//|   * A session never implies a direction. A direction exists only |
//|     after displacement + MSS are confirmed on a reversal leg.    |
//|   * Both sides can be armed at once (both-sides model).          |
//|   * No chart calls here: reusable from an EA / script.           |
//+------------------------------------------------------------------+
#ifndef NTA_DLS_ENGINE_MQH
#define NTA_DLS_ENGINE_MQH

#include "DLS_Types.mqh"

#define DLS_RING_CAP 64

class CDlsEngine
  {
public:
   SDlsSettings      s;
   SDlsDay           days[];
   int               dayCount;
   SDlsEvent         events[];
   int               evCount;
   SDlsFvg           fvgs[];
   int               fvgCount;
   SDlsSwing         swings[];
   int               swingCount;
   int               periodSec;
   bool              journal;          // print events to the Experts log
   string            journalPrefix;

private:
   // story-minute windows (0 = story day start)
   int               m_aS, m_aE, m_lS, m_lE, m_nS, m_nE, m_cut, m_eval;
   int               m_sbAmS, m_sbAmE, m_sbPmS, m_sbPmE, m_sbLonS, m_sbLonE;
   // ATR (Wilder) and average body
   double            m_atr;
   int               m_atrN;
   double            m_trSum;
   double            m_bodyRing[];
   int               m_bodyIdx, m_bodyN;
   double            m_bodySum;
   double            m_prevClose;
   bool              m_havePrev;
   // bar ring buffer
   datetime          m_rT[DLS_RING_CAP];
   double            m_rO[DLS_RING_CAP], m_rH[DLS_RING_CAP], m_rL[DLS_RING_CAP], m_rC[DLS_RING_CAP];
   int               m_rHead, m_rCount;
   datetime          m_lastTime;
   // FVG found on the current bar
   bool              m_barFvgBull, m_barFvgBear;
   double            m_bullTop, m_bullBot, m_bearTop, m_bearBot;
   datetime          m_fvgMid;
   // per bar context
   double            m_atrPrev, m_bodyPrev;

public:
                     CDlsEngine(void) { dayCount = 0; evCount = 0; fvgCount = 0; swingCount = 0; periodSec = 60; journal = false; journalPrefix = ""; }

   void              Init(const SDlsSettings &st, const int period_seconds)
     {
      s = st;
      periodSec = MathMax(60, period_seconds);
      if(s.swingStrength < 1) s.swingStrength = 1;
      if(s.swingStrength > 10) s.swingStrength = 10;
      if(s.acceptBars < 1) s.acceptBars = 1;
      if(s.avgBodyPeriod < 1) s.avgBodyPeriod = 1;
      if(s.atrPeriod < 1) s.atrPeriod = 1;

      m_aS = ToSm(s.asiaStart);    m_aE = WinEnd(m_aS, ToSm(s.asiaEnd));
      m_lS = ToSm(s.londonStart);  m_lE = WinEnd(m_lS, ToSm(s.londonEnd));
      m_nS = ToSm(s.nyStart);      m_nE = WinEnd(m_nS, ToSm(s.nyEnd));
      m_cut  = PointSm(s.nyCutoff);
      m_eval = PointSm(s.evalEnd);
      if(m_cut < m_nE)    m_cut = m_nE;
      if(m_eval < m_cut)  m_eval = m_cut;
      m_sbAmS  = ToSm(s.sbAmStart);  m_sbAmE  = WinEnd(m_sbAmS,  ToSm(s.sbAmEnd));
      m_sbPmS  = ToSm(s.sbPmStart);  m_sbPmE  = WinEnd(m_sbPmS,  ToSm(s.sbPmEnd));
      m_sbLonS = ToSm(s.sbLonStart); m_sbLonE = WinEnd(m_sbLonS, ToSm(s.sbLonEnd));
      Reset();
     }

   void              Reset(void)
     {
      ArrayResize(days, 0);    dayCount = 0;
      ArrayResize(events, 0);  evCount = 0;
      ArrayResize(fvgs, 0);    fvgCount = 0;
      ArrayResize(swings, 0);  swingCount = 0;
      m_atr = 0; m_atrN = 0; m_trSum = 0;
      ArrayResize(m_bodyRing, s.avgBodyPeriod);
      ArrayInitialize(m_bodyRing, 0.0);
      m_bodyIdx = 0; m_bodyN = 0; m_bodySum = 0;
      m_prevClose = 0; m_havePrev = false;
      m_rHead = -1; m_rCount = 0;
      m_lastTime = 0;
     }

   //--- window sanity (London inside Asia etc. is a configuration error)
   bool              WindowsValid(string &why)
     {
      if(m_aE > m_lS)  { why = "Asia window must end before London starts";     return false; }
      if(m_lE > m_nS)  { why = "London window must end before New York starts";  return false; }
      return true;
     }

   double            Atr(void) const { return m_atr; }
   int               StoryMinute(const datetime t) const { return (int)((ShiftedTime(t) % 86400) / 60); }
   int               DayKeyOf(const datetime t) const    { return (int)(ShiftedTime(t) / 86400); }
   bool              InSilverBullet(const datetime t) const
     {
      int sm = StoryMinute(t);
      if(s.sbAmOn  && sm >= m_sbAmS  && sm < m_sbAmE)  return true;
      if(s.sbPmOn  && sm >= m_sbPmS  && sm < m_sbPmE)  return true;
      if(s.sbLonOn && sm >= m_sbLonS && sm < m_sbLonE) return true;
      return false;
     }
   //--- server time of a story minute on a given day key
   datetime          TimeOfStoryMinute(const int dayKey, const int sm) const
     {
      long shifted = (long)dayKey * 86400 + (long)sm * 60;
      return (datetime)(shifted - (long)s.serverToNyHours * 3600 + (long)s.dayStartMin * 60);
     }
   int               NyStartSm(void) const  { return m_nS; }
   int               NyCutoffSm(void) const { return m_cut; }
   int               EvalEndSm(void) const  { return m_eval; }

   //--- trading date (NY calendar) of a story day, "YYYY.MM.DD"
   string            DayDateText(const int dayKey) const
     {
      datetime d = (datetime)((long)dayKey * 86400 + (long)s.dayStartMin * 60 + 86399);
      return TimeToString(d, TIME_DATE);
     }

   double            RetraceLevelOf(const SDlsLeg &lg) const
     {
      double mid = (lg.fvgTop + lg.fvgBottom) * 0.5;
      if(s.retraceLevel == DLS_RT_CE) return mid;
      bool proximal = (s.retraceLevel == DLS_RT_PROXIMAL);
      if(lg.dir < 0) return proximal ? lg.fvgBottom : lg.fvgTop;
      return proximal ? lg.fvgTop : lg.fvgBottom;
     }

   //+---------------------------------------------------------------+
   //| Feed one CLOSED bar (chronological order)                      |
   //| refAtr : higher-timeframe ATR used for the Asia range ratio    |
   //+---------------------------------------------------------------+
   void              OnBar(const datetime t, const double o, const double h, const double l, const double c, const double refAtr)
     {
      if(t <= m_lastTime)
         return;
      m_lastTime = t;
      m_atrPrev  = m_atr;
      m_bodyPrev = (m_bodyN > 0) ? m_bodySum / m_bodyN : 0.0;

      PushRing(t, o, h, l, c);
      DetectSwing();
      UpdateSwingsTaken(h, l);

      int key = DayKeyOf(t);
      if(dayCount == 0 || days[dayCount - 1].dayKey != key)
         NewDay(key, t);
      int cur = dayCount - 1;

      DetectFvg(cur);
      ProcessBar(days[cur], cur, t, o, h, l, c, StoryMinute(t), refAtr);

      UpdateAtrBody(o, h, l, c);
     }

   //--- finalize the running day (e.g. end of a backtest)
   void              FinalizeCurrent(void)
     {
      if(dayCount > 0)
         FinalizeDay(days[dayCount - 1], dayCount - 1);
     }

   string            EventText(const SDlsEvent &e)
     {
      string lv = DlsLiquidityName(e.levelKind);
      switch(e.type)
        {
         case DLS_EV_ASIA_LOCKED:     return "ASIA LIQUIDITY CREATED";
         case DLS_EV_LONDON_LOCKED:   return "LONDON LIQUIDITY LOCKED";
         case DLS_EV_LEVEL_TAKEN:
            if(e.detail == DLS_LVS_WICK_SWEPT) return lv + " WICK SWEPT (" + DlsSessionText(e.session) + ")";
            if(e.detail == DLS_LVS_ACCEPTED)   return lv + " BROKEN / ACCEPTED (" + DlsSessionText(e.session) + ")";
            return lv + " TRADED THROUGH (" + DlsSessionText(e.session) + ")";
         case DLS_EV_LEVEL_RECLAIMED: return lv + " RECLAIMED";
         case DLS_EV_LEVEL_ACCEPTED:  return lv + " BROKEN / ACCEPTED";
         case DLS_EV_NY_SWEEP:        return "NY SWEPT " + lv + " -> WAIT " + DlsDirText(e.dir) + " DISPLACEMENT";
         case DLS_EV_BOTH_SIDES:      return "BOTH SIDES LIQUIDITY TAKEN - WAIT FOR STRUCTURE";
         case DLS_EV_DISPLACEMENT:    return DlsDirText(e.dir) + " DISPLACEMENT";
         case DLS_EV_MSS:             return DlsDirText(e.dir) + " MSS CONFIRMED";
         case DLS_EV_STORY_FVG:       return DlsDirText(e.dir) + " STORY FVG";
         case DLS_EV_RETRACE:         return "FVG RETRACED - STORY CONDITIONS COMPLETE";
         case DLS_EV_LEG_FAILED:      return "LIQUIDITY SWEPT - NO REVERSAL CONFIRMATION (" + DlsFailText(e.detail) + ")";
         case DLS_EV_INVALIDATED:     return "STORY INVALIDATED";
         case DLS_EV_STORY_STALLED:   return (e.detail == DLS_ST_NO_FVG) ? "MSS WITHOUT STORY FVG" : "FVG NOT RETRACED BEFORE CUTOFF";
        }
      return "";
     }

private:
   //--- clock helpers ------------------------------------------------
   long              ShiftedTime(const datetime t) const
     {
      return (long)t + (long)s.serverToNyHours * 3600 - (long)s.dayStartMin * 60;
     }
   int               ToSm(const int nyMin) const { return ((nyMin - s.dayStartMin) % 1440 + 1440) % 1440; }
   int               WinEnd(const int startSm, const int endSm) const { return (endSm <= startSm) ? endSm + 1440 : endSm; }
   int               PointSm(const int nyMin) const { int v = ToSm(nyMin); return (v == 0) ? 1440 : v; }

   int               SessionOf(const int sm) const
     {
      if(sm >= m_aS && sm < m_aE) return DLS_SES_ASIA;
      if(sm >= m_lS && sm < m_lE) return DLS_SES_LONDON;
      if(sm >= m_nS && sm < m_nE) return DLS_SES_NY;
      if(sm < m_lS)               return DLS_SES_PRE_LONDON;
      if(sm < m_nS)               return DLS_SES_PRE_NY;
      return DLS_SES_POST_NY;
     }

   //--- ring buffer (k = 0 is the newest bar) --------------------------
   void              PushRing(const datetime t, const double o, const double h, const double l, const double c)
     {
      m_rHead = (m_rHead + 1) % DLS_RING_CAP;
      m_rT[m_rHead] = t; m_rO[m_rHead] = o; m_rH[m_rHead] = h; m_rL[m_rHead] = l; m_rC[m_rHead] = c;
      if(m_rCount < DLS_RING_CAP) m_rCount++;
     }
   int               RI(const int k) const { return (m_rHead - k + DLS_RING_CAP) % DLS_RING_CAP; }
   double            RH(const int k) const { return m_rH[RI(k)]; }
   double            RL(const int k) const { return m_rL[RI(k)]; }
   datetime          RT(const int k) const { return m_rT[RI(k)]; }

   void              UpdateAtrBody(const double o, const double h, const double l, const double c)
     {
      double tr = h - l;
      if(m_havePrev)
         tr = MathMax(tr, MathMax(MathAbs(h - m_prevClose), MathAbs(l - m_prevClose)));
      if(m_atrN < s.atrPeriod)
        {
         m_trSum += tr;
         m_atrN++;
         if(m_atrN == s.atrPeriod)
            m_atr = m_trSum / s.atrPeriod;
        }
      else
         m_atr = (m_atr * (s.atrPeriod - 1) + tr) / s.atrPeriod;
      m_prevClose = c;
      m_havePrev = true;

      double body = MathAbs(c - o);
      if(m_bodyN < s.avgBodyPeriod)
         m_bodyN++;
      else
         m_bodySum -= m_bodyRing[m_bodyIdx];
      m_bodyRing[m_bodyIdx] = body;
      m_bodySum += body;
      m_bodyIdx = (m_bodyIdx + 1) % s.avgBodyPeriod;
     }

   //--- confirmed fractal swings (no look-ahead: confirmed R bars later)
   void              DetectSwing(void)
     {
      int R = s.swingStrength;
      int L = s.swingStrength;
      if(m_rCount < L + R + 1)
         return;
      int k = R;
      double ph = RH(k), pl = RL(k);
      bool isH = true, isL = true;
      for(int j = 1; j <= R; j++)
        {
         if(RH(k - j) > ph) isH = false;
         if(RL(k - j) < pl) isL = false;
        }
      for(int j = 1; j <= L; j++)
        {
         if(RH(k + j) >= ph) isH = false;
         if(RL(k + j) <= pl) isL = false;
        }
      if(isH) AddSwing(RT(k), ph, true);
      if(isL) AddSwing(RT(k), pl, false);
     }

   void              AddSwing(const datetime t, const double p, const bool isHigh)
     {
      if(swingCount >= 600)
        {
         SDlsSwing tmp[];
         ArrayResize(tmp, 300);
         for(int i = 0; i < 300; i++) tmp[i] = swings[swingCount - 300 + i];
         ArrayResize(swings, 300);
         for(int i = 0; i < 300; i++) swings[i] = tmp[i];
         swingCount = 300;
        }
      ArrayResize(swings, swingCount + 1, 128);
      swings[swingCount].time = t;
      swings[swingCount].confirmTime = m_lastTime;
      swings[swingCount].price = p;
      swings[swingCount].isHigh = isHigh;
      swings[swingCount].taken = false;
      swingCount++;
     }

   void              UpdateSwingsTaken(const double h, const double l)
     {
      int stop = MathMax(0, swingCount - 60);
      for(int i = swingCount - 1; i >= stop; i--)
        {
         if(swings[i].taken) continue;
         if(swings[i].isHigh && h > swings[i].price) swings[i].taken = true;
         if(!swings[i].isHigh && l < swings[i].price) swings[i].taken = true;
        }
     }

   //--- 3-candle FVG ending on the current bar
   void              DetectFvg(const int dayIdx)
     {
      m_barFvgBull = false;
      m_barFvgBear = false;
      if(m_rCount < 3)
         return;
      double minSize = s.fvgMinAtr * m_atrPrev;
      m_fvgMid = RT(1);
      if(RL(0) > RH(2) && RL(0) - RH(2) >= minSize)
        {
         m_barFvgBull = true;
         m_bullTop = RL(0);
         m_bullBot = RH(2);
         AddFvg(dayIdx, +1, m_bullTop, m_bullBot);
        }
      if(RH(0) < RL(2) && RL(2) - RH(0) >= minSize)
        {
         m_barFvgBear = true;
         m_bearTop = RL(2);
         m_bearBot = RH(0);
         AddFvg(dayIdx, -1, m_bearTop, m_bearBot);
        }
     }

   void              AddFvg(const int dayIdx, const int dir, const double top, const double bot)
     {
      if(fvgCount >= 20000)
        {
         SDlsFvg tmp[];
         ArrayResize(tmp, 10000);
         for(int i = 0; i < 10000; i++) tmp[i] = fvgs[fvgCount - 10000 + i];
         ArrayResize(fvgs, 10000);
         for(int i = 0; i < 10000; i++) fvgs[i] = tmp[i];
         fvgCount = 10000;
        }
      ArrayResize(fvgs, fvgCount + 1, 512);
      fvgs[fvgCount].day = dayIdx;
      fvgs[fvgCount].dir = dir;
      fvgs[fvgCount].time = m_fvgMid;
      fvgs[fvgCount].formTime = m_lastTime;
      fvgs[fvgCount].top = top;
      fvgs[fvgCount].bottom = bot;
      fvgs[fvgCount].story = false;
      fvgCount++;
     }

   void              MarkStoryFvg(const int dir, const datetime mid)
     {
      for(int i = fvgCount - 1; i >= 0 && i >= fvgCount - 50; i--)
         if(fvgs[i].dir == dir && fvgs[i].time == mid)
           {
            fvgs[i].story = true;
            return;
           }
     }

   //--- events ---------------------------------------------------------
   void              AddEvent(const int dayIdx, const datetime t, const double price, const int type, const int dir, const int levelKind, const int session, const int detail)
     {
      ArrayResize(events, evCount + 1, 256);
      events[evCount].day = dayIdx;
      events[evCount].time = t;
      events[evCount].price = price;
      events[evCount].type = type;
      events[evCount].dir = dir;
      events[evCount].levelKind = levelKind;
      events[evCount].session = session;
      events[evCount].detail = detail;
      if(journal)
         PrintFormat("%s[%s %s] %s @ %s", journalPrefix, DayDateText(days[dayIdx].dayKey),
                     TimeToString(t, TIME_MINUTES), EventText(events[evCount]), DoubleToString(price, _Digits));
      evCount++;
     }

   //--- day lifecycle --------------------------------------------------
   void              NewDay(const int key, const datetime t)
     {
      int prev = dayCount - 1;
      if(prev >= 0)
         FinalizeDay(days[prev], prev);

      ArrayResize(days, dayCount + 1, 64);
      ZeroMemory(days[dayCount]);
      days[dayCount].dayKey = key;
      days[dayCount].firstBarTime = t;
      days[dayCount].state = DLS_DAY_START;
      days[dayCount].transient = -1;
      days[dayCount].leg[DLS_LEG_BEAR].dir = -1;
      days[dayCount].leg[DLS_LEG_BULL].dir = +1;
      for(int k = 0; k < DLS_LEVEL_SLOTS; k++)
         days[dayCount].lv[k].isHigh = (k == DLS_LV_ASIA_HIGH || k == DLS_LV_LONDON_HIGH || k == DLS_LV_PDH || k == DLS_LV_SWING_HIGH);
      if(prev >= 0 && days[prev].lastBarTime > 0)
        {
         days[dayCount].lv[DLS_LV_PDH].valid = true;
         days[dayCount].lv[DLS_LV_PDH].price = days[prev].dayHigh;
         days[dayCount].lv[DLS_LV_PDH].originTime = days[prev].firstBarTime;
         days[dayCount].lv[DLS_LV_PDH].lockTime = t;
         days[dayCount].lv[DLS_LV_PDL].valid = true;
         days[dayCount].lv[DLS_LV_PDL].price = days[prev].dayLow;
         days[dayCount].lv[DLS_LV_PDL].originTime = days[prev].firstBarTime;
         days[dayCount].lv[DLS_LV_PDL].lockTime = t;
        }
      dayCount++;
     }

   void              FinalizeDay(SDlsDay &d, const int idx)
     {
      if(d.finalized)
         return;
      if(d.asiaStarted && !d.asiaLocked)
         LockAsia(d, idx, d.lastBarTime, 0.0);
      if(d.lonStarted && !d.lonLocked)
         LockLondon(d, idx, d.lastBarTime);
      if(!d.nyCutoffDone)
         CutoffNy(d, idx, d.lastBarTime);
      d.evalDone = true;
      d.fOppositeLondonSwept =
         (d.londonStory == DLS_LS_SWEPT_ASIA_LOW  && d.lv[DLS_LV_LONDON_HIGH].takenBy == DLS_SES_NY) ||
         (d.londonStory == DLS_LS_SWEPT_ASIA_HIGH && d.lv[DLS_LV_LONDON_LOW].takenBy  == DLS_SES_NY);
      d.transient = -1;
      d.state = DeriveState(d, 1440);
      d.finalized = true;
     }

   //--- main per-bar routine for the current day ----------------------
   void              ProcessBar(SDlsDay &d, const int idx, const datetime t, const double o, const double h, const double l, const double c, const int sm, const double refAtr)
     {
      d.transient = -1;
      int ses = SessionOf(sm);

      // ---------------- ASIA: liquidity creation ----------------
      if(ses == DLS_SES_ASIA)
        {
         if(!d.asiaStarted)
           {
            d.asiaStarted = true;
            d.asiaStartTime = t;
            d.asiaHigh = h; d.asiaHighTime = t;
            d.asiaLow = l;  d.asiaLowTime = t;
           }
         else
           {
            if(h > d.asiaHigh) { d.asiaHigh = h; d.asiaHighTime = t; }
            if(l < d.asiaLow)  { d.asiaLow = l;  d.asiaLowTime = t; }
           }
         d.asiaEndTime = t + periodSec;
        }
      else if(d.asiaStarted && !d.asiaLocked && sm >= m_aE)
         LockAsia(d, idx, t, refAtr);

      // ---------------- LONDON: builds new liquidity -------------
      if(ses == DLS_SES_LONDON)
        {
         if(!d.lonStarted)
           {
            d.lonStarted = true;
            d.lonStartTime = t;
            d.lonHigh = h; d.lonHighTime = t;
            d.lonLow = l;  d.lonLowTime = t;
           }
         else
           {
            if(h > d.lonHigh) { d.lonHigh = h; d.lonHighTime = t; }
            if(l < d.lonLow)  { d.lonLow = l;  d.lonLowTime = t; }
           }
         d.lonEndTime = t + periodSec;
        }
      else if(d.lonStarted && !d.lonLocked && sm >= m_lE)
         LockLondon(d, idx, t);

      // ---------------- NEW YORK --------------------------------
      if(!d.nyStarted && sm >= m_nS && sm < m_cut)
         StartNy(d, t, o);
      if(d.nyStarted && !d.nyWindowClosed && sm >= m_nE)
         d.nyWindowClosed = true;
      if(d.nyStarted && !d.nyCutoffDone && sm >= m_cut)
         CutoffNy(d, idx, t);
      if(d.committed && d.storyStage == DLS_ST_COMPLETE && !d.evalDone && sm >= m_eval)
         d.evalDone = true;

      // ---------------- liquidity level life cycle ---------------
      double buf = (s.bufferMode == DLS_BUF_ATR) ? s.bufferValue * m_atrPrev : s.bufferValue;
      for(int k = 0; k < DLS_LEVEL_SLOTS; k++)
        {
         if(!d.lv[k].valid || !d.lv[k].monitoring)
            continue;
         int r = UpdateLevel(d.lv[k], t, h, l, c, buf, ses);
         if(r == 1)
           {
            AddEvent(idx, t, d.lv[k].price, DLS_EV_LEVEL_TAKEN, d.lv[k].isHigh ? -1 : +1, k, ses, d.lv[k].status);
            if(ses == DLS_SES_LONDON && d.londonFirstSide == 0 && (k == DLS_LV_ASIA_HIGH || k == DLS_LV_ASIA_LOW))
               d.londonFirstSide = (k == DLS_LV_ASIA_HIGH) ? +1 : -1;
            if(ses == DLS_SES_NY && d.nyStarted && !d.nyWindowClosed && !d.nyCutoffDone && d.lv[k].nyTarget)
               ArmLeg(d, idx, k, t, h, l);
           }
         else if(r == 2)
            AddEvent(idx, t, d.lv[k].price, DLS_EV_LEVEL_RECLAIMED, d.lv[k].isHigh ? -1 : +1, k, ses, d.lv[k].status);
         else if(r == 3)
            AddEvent(idx, t, d.lv[k].price, DLS_EV_LEVEL_ACCEPTED, d.lv[k].isHigh ? +1 : -1, k, ses, d.lv[k].status);
        }

      // ---------------- reversal legs (pre-commit) ---------------
      if(d.nyStarted && !d.committed && !d.nyCutoffDone)
        {
         for(int li = 0; li < 2 && !d.committed; li++)
            StepLeg(d, idx, li, t, o, h, l, c);
         d.bothSidesActive = LegActive(d.leg[0]) && LegActive(d.leg[1]);
        }

      // ---------------- committed story --------------------------
      if(d.committed)
         StepStory(d, idx, t, h, l, c);

      // ---------------- bookkeeping ------------------------------
      if(d.lastBarTime == 0)
        {
         d.dayHigh = h;
         d.dayLow = l;
        }
      else
        {
         d.dayHigh = MathMax(d.dayHigh, h);
         d.dayLow = MathMin(d.dayLow, l);
        }
      if(!d.nyStarted)
        {
         d.preNyHigh = d.dayHigh;
         d.preNyLow = d.dayLow;
        }
      d.lastBarTime = t;
      d.state = DeriveState(d, sm);
      if(d.transient >= 0)
         d.state = d.transient;
     }

   //--- ASIA lock: levels become fixed BSL / SSL -----------------------
   void              LockAsia(SDlsDay &d, const int idx, const datetime t, const double refAtr)
     {
      d.asiaLocked = true;
      double range = d.asiaHigh - d.asiaLow;
      d.asiaRefAtr = refAtr;
      d.asiaRatio = (refAtr > 0) ? range / refAtr : 0.0;
      if(refAtr <= 0)                        d.asiaClass = DLS_RANGE_UNKNOWN;
      else if(d.asiaRatio < s.narrowRatio)   d.asiaClass = DLS_RANGE_NARROW;
      else if(d.asiaRatio > s.wideRatio)     d.asiaClass = DLS_RANGE_WIDE;
      else                                   d.asiaClass = DLS_RANGE_NORMAL;

      SetLevel(d.lv[DLS_LV_ASIA_HIGH], d.asiaHigh, d.asiaHighTime, t);
      SetLevel(d.lv[DLS_LV_ASIA_LOW],  d.asiaLow,  d.asiaLowTime,  t);
      AddEvent(idx, t, d.asiaHigh, DLS_EV_ASIA_LOCKED, 0, DLS_LV_ASIA_HIGH, DLS_SES_ASIA, d.asiaClass);
      d.transient = DLS_ASIA_LOCKED;
     }

   //--- LONDON lock: story of what London did with Asia ----------------
   void              LockLondon(SDlsDay &d, const int idx, const datetime t)
     {
      d.lonLocked = true;
      SetLevel(d.lv[DLS_LV_LONDON_HIGH], d.lonHigh, d.lonHighTime, t);
      SetLevel(d.lv[DLS_LV_LONDON_LOW],  d.lonLow,  d.lonLowTime,  t);

      bool hiTaken = d.lv[DLS_LV_ASIA_HIGH].valid && d.lv[DLS_LV_ASIA_HIGH].takenBy == DLS_SES_LONDON;
      bool loTaken = d.lv[DLS_LV_ASIA_LOW].valid  && d.lv[DLS_LV_ASIA_LOW].takenBy  == DLS_SES_LONDON;
      bool hiSwept = hiTaken && DlsIsSwept(d.lv[DLS_LV_ASIA_HIGH].status);
      bool loSwept = loTaken && DlsIsSwept(d.lv[DLS_LV_ASIA_LOW].status);

      if(hiTaken && loTaken) d.raid = DLS_ASIA_BOTH_SWEPT;
      else if(hiTaken)       d.raid = DLS_ASIA_HIGH_SWEPT;
      else if(loTaken)       d.raid = DLS_ASIA_LOW_SWEPT;
      else                   d.raid = DLS_ASIA_NOT_SWEPT;

      if(hiTaken && loTaken)
         d.londonStory = DLS_LS_SWEPT_BOTH;
      else if(hiTaken)
         d.londonStory = hiSwept ? DLS_LS_SWEPT_ASIA_HIGH : DLS_LS_BROKE_ASIA_HIGH;
      else if(loTaken)
         d.londonStory = loSwept ? DLS_LS_SWEPT_ASIA_LOW : DLS_LS_BROKE_ASIA_LOW;
      else if(d.asiaLocked && d.lonHigh <= d.asiaHigh && d.lonLow >= d.asiaLow)
         d.londonStory = DLS_LS_INSIDE_ASIA;
      else
         d.londonStory = DLS_LS_NO_CLEAR_EVENT;

      AddEvent(idx, t, d.lonHigh, DLS_EV_LONDON_LOCKED, 0, DLS_LV_LONDON_HIGH, DLS_SES_LONDON, d.londonStory);
      d.transient = DLS_LONDON_LOCKED;
     }

   void              SetLevel(SDlsLevel &v, const double price, const datetime origin, const datetime lockT)
     {
      v.valid = true;
      v.monitoring = true;
      v.price = price;
      v.originTime = origin;
      v.lockTime = lockT;
      v.status = DLS_LVS_ACTIVE;
      v.takenBy = DLS_SES_NONE;
      v.closesBeyond = 0;
     }

   //--- NY open: carry the whole context, build the target list --------
   void              StartNy(SDlsDay &d, const datetime t, const double o)
     {
      d.nyStarted = true;
      d.nyStartTime = t;
      // Asia / London: still untouched liquidity only
      int carry[4] = {DLS_LV_ASIA_HIGH, DLS_LV_ASIA_LOW, DLS_LV_LONDON_HIGH, DLS_LV_LONDON_LOW};
      for(int i = 0; i < 4; i++)
        {
         int k = carry[i];
         if(!d.lv[k].valid) continue;
         d.lv[k].nyTarget = (d.lv[k].status == DLS_LVS_ACTIVE) && (d.lv[k].isHigh ? o < d.lv[k].price : o > d.lv[k].price);
        }
      // PDH / PDL: not raided earlier today
      if(d.lv[DLS_LV_PDH].valid)
        {
         d.lv[DLS_LV_PDH].monitoring = true;
         d.lv[DLS_LV_PDH].nyTarget = (d.lastBarTime == 0 || d.dayHigh < d.lv[DLS_LV_PDH].price) && o < d.lv[DLS_LV_PDH].price;
        }
      if(d.lv[DLS_LV_PDL].valid)
        {
         d.lv[DLS_LV_PDL].monitoring = true;
         d.lv[DLS_LV_PDL].nyTarget = (d.lastBarTime == 0 || d.dayLow > d.lv[DLS_LV_PDL].price) && o > d.lv[DLS_LV_PDL].price;
        }
      // most recent confirmed, untaken swings
      for(int side = 0; side < 2; side++)
        {
         bool wantHigh = (side == 0);
         int k = wantHigh ? DLS_LV_SWING_HIGH : DLS_LV_SWING_LOW;
         for(int i = swingCount - 1; i >= 0; i--)
           {
            if(swings[i].isHigh != wantHigh || swings[i].taken || swings[i].time >= t)
               continue;
            if(wantHigh ? swings[i].price <= o : swings[i].price >= o)
               continue;
            if(DuplicatesLevel(d, swings[i].price, k))
               break;
            SetLevel(d.lv[k], swings[i].price, swings[i].time, t);
            d.lv[k].nyTarget = true;
            break;
           }
        }
     }

   bool              DuplicatesLevel(SDlsDay &d, const double price, const int except)
     {
      double eps = MathMax(_Point, m_atrPrev * 0.02);
      for(int k = 0; k < DLS_LEVEL_SLOTS; k++)
         if(k != except && d.lv[k].valid && d.lv[k].nyTarget && MathAbs(d.lv[k].price - price) <= eps)
            return true;
      return false;
     }

   //--- level life cycle: 0 none, 1 taken, 2 reclaimed, 3 accepted ----
   int               UpdateLevel(SDlsLevel &v, const datetime t, const double h, const double l, const double c, const double buf, const int ses)
     {
      bool beyond      = v.isHigh ? (h > v.price + buf) : (l < v.price - buf);
      bool closeBeyond = v.isHigh ? (c > v.price) : (c < v.price);
      if(v.status != DLS_LVS_ACTIVE)
         v.extreme = v.isHigh ? MathMax(v.extreme, h) : MathMin(v.extreme, l);

      switch(v.status)
        {
         case DLS_LVS_ACTIVE:
            if(!beyond)
               return 0;
            v.takenBy = ses;
            v.takenTime = t;
            v.extreme = v.isHigh ? h : l;
            if(closeBeyond)
              {
               v.closesBeyond = 1;
               if(s.acceptBars <= 1)
                 {
                  v.status = DLS_LVS_ACCEPTED;
                  v.resolvedTime = t;
                 }
               else
                  v.status = DLS_LVS_PENDING;
              }
            else
              {
               v.status = DLS_LVS_WICK_SWEPT;
               v.closesBeyond = 0;
               v.resolvedTime = t;
              }
            return 1;

         case DLS_LVS_PENDING:
            if(closeBeyond)
              {
               v.closesBeyond++;
               if(v.closesBeyond >= s.acceptBars)
                 {
                  v.status = DLS_LVS_ACCEPTED;
                  v.resolvedTime = t;
                  return 3;
                 }
               return 0;
              }
            v.status = DLS_LVS_RECLAIMED;
            v.resolvedTime = t;
            v.closesBeyond = 0;
            return 2;

         case DLS_LVS_WICK_SWEPT:
         case DLS_LVS_RECLAIMED:
            if(closeBeyond)
              {
               v.closesBeyond++;
               if(v.closesBeyond >= s.acceptBars)
                 {
                  v.status = DLS_LVS_ACCEPTED;
                  v.resolvedTime = t;
                  return 3;
                 }
              }
            else
               v.closesBeyond = 0;
            return 0;
        }
      return 0;
     }

   //--- NY liquidity sweep arms a reversal leg (opposite direction) ----
   void              ArmLeg(SDlsDay &d, const int idx, const int k, const datetime t, const double h, const double l)
     {
      bool isHigh = d.lv[k].isHigh;
      if(isHigh) d.nyTookBsl = true; else d.nyTookSsl = true;
      d.fNySweep = true;
      if(d.committed)
         return;
      int li = isHigh ? DLS_LEG_BEAR : DLS_LEG_BULL;
      double ext = isHigh ? h : l;

      d.leg[li].sweptMask |= (1 << k);
      d.leg[li].sweepCount++;
      bool rearm = true;
      if(d.leg[li].stage == DLS_LEG_WAIT_MSS)
         rearm = isHigh ? (ext > d.leg[li].sweepExtreme) : (ext < d.leg[li].sweepExtreme);
      if(rearm)
        {
         d.leg[li].stage = DLS_LEG_WAIT_DISP;
         d.leg[li].fail = DLS_FAIL_NONE;
         d.leg[li].failTime = 0;
         d.leg[li].levelKind = k;
         d.leg[li].levelPrice = d.lv[k].price;
         d.leg[li].sweepTime = t;
         d.leg[li].sweepExtreme = ext;
         d.leg[li].barsSinceSweep = 0;
         d.leg[li].dispTime = 0;
         d.leg[li].barsSinceDisp = 0;
         d.leg[li].mssLevel = 0;
         d.leg[li].mssSwingTime = 0;
         d.leg[li].mssTime = 0;
         d.leg[li].fvgFound = false;
        }
      AddEvent(idx, t, d.lv[k].price, DLS_EV_NY_SWEEP, d.leg[li].dir, k, DLS_SES_NY, 0);
      d.transient = DLS_NY_LIQUIDITY_SWEPT;

      int other = 1 - li;
      if(LegActive(d.leg[other]) && !d.bothSidesActive)
        {
         d.bothSidesActive = true;
         AddEvent(idx, t, d.lv[k].price, DLS_EV_BOTH_SIDES, 0, k, DLS_SES_NY, 0);
         d.transient = DLS_NY_BOTH_SIDES_TAKEN;
        }
     }

   bool              LegActive(const SDlsLeg &lg) const
     {
      return lg.stage == DLS_LEG_WAIT_DISP || lg.stage == DLS_LEG_WAIT_MSS;
     }

   bool              IsDisplacement(const int dir, const double o, const double c) const
     {
      if(dir < 0 && c >= o) return false;
      if(dir > 0 && c <= o) return false;
      double body = MathAbs(c - o);
      bool byAtr  = (m_atrPrev > 0)  && body >= m_atrPrev * s.dispAtrFactor;
      bool byBody = (m_bodyPrev > 0) && body >= m_bodyPrev * s.bodyMultiplier;
      switch(s.dispMode)
        {
         case DLS_DISP_ATR:    return byAtr;
         case DLS_DISP_BODY:   return byBody;
         case DLS_DISP_BOTH:   return byAtr && byBody;
         case DLS_DISP_EITHER: return byAtr || byBody;
        }
      return false;
     }

   //--- nearest confirmed swing before displacement (bearish -> low)
   bool              FindMssSwing(const int dir, const datetime dispTime, double &price, datetime &swingTime) const
     {
      bool wantHigh = (dir > 0);
      datetime oldest = dispTime - (datetime)(s.mssSwingLookback * periodSec);
      for(int i = swingCount - 1; i >= 0; i--)
        {
         if(swings[i].isHigh != wantHigh) continue;
         if(swings[i].time >= dispTime || swings[i].confirmTime > dispTime) continue;
         if(swings[i].time < oldest) break;
         price = swings[i].price;
         swingTime = swings[i].time;
         return true;
        }
      return false;
     }

   void              FailLeg(SDlsDay &d, const int idx, const int li, const int reason, const datetime t, const double price)
     {
      d.leg[li].stage = DLS_LEG_FAILED;
      d.leg[li].fail = reason;
      d.leg[li].failTime = t;
      d.fNoReversal = true;
      AddEvent(idx, t, price, DLS_EV_LEG_FAILED, d.leg[li].dir, d.leg[li].levelKind, DLS_SES_NY, reason);
     }

   void              StepLeg(SDlsDay &d, const int idx, const int li, const datetime t, const double o, const double h, const double l, const double c)
     {
      if(!LegActive(d.leg[li]))
         return;
      int dir = d.leg[li].dir;
      if(t != d.leg[li].sweepTime)
         d.leg[li].barsSinceSweep++;

      // price accepted beyond the swept level: it was a breakout, not a sweep
      if(d.lv[d.leg[li].levelKind].status == DLS_LVS_ACCEPTED)
        {
         FailLeg(d, idx, li, DLS_FAIL_ACCEPTANCE, t, c);
         return;
        }

      if(d.leg[li].stage == DLS_LEG_WAIT_DISP)
        {
         if(dir < 0) d.leg[li].sweepExtreme = MathMax(d.leg[li].sweepExtreme, h);
         else        d.leg[li].sweepExtreme = MathMin(d.leg[li].sweepExtreme, l);

         if(!IsDisplacement(dir, o, c))
           {
            if(d.leg[li].barsSinceSweep >= s.dispMaxBars)
               FailLeg(d, idx, li, DLS_FAIL_NO_DISPLACEMENT, t, c);
            return;
           }
         d.leg[li].stage = DLS_LEG_WAIT_MSS;
         d.leg[li].dispTime = t;
         d.leg[li].dispOpen = o;
         d.leg[li].dispClose = c;
         d.leg[li].dispBody = MathAbs(c - o);
         d.leg[li].dispAtr = (m_atrPrev > 0) ? d.leg[li].dispBody / m_atrPrev : 0.0;
         d.leg[li].barsSinceDisp = 0;
         double sp = 0;
         datetime st = 0;
         if(FindMssSwing(dir, t, sp, st))
           {
            d.leg[li].mssLevel = sp;
            d.leg[li].mssSwingTime = st;
           }
         d.fDisp = true;
         AddEvent(idx, t, c, DLS_EV_DISPLACEMENT, dir, d.leg[li].levelKind, DLS_SES_NY, 0);
         d.transient = DLS_DISPLACEMENT_CONFIRMED;
        }

      // ---- WAIT_MSS
      bool dispBar = (t == d.leg[li].dispTime);
      if(!dispBar)
         d.leg[li].barsSinceDisp++;

      // first same-direction FVG created from the displacement onwards
      if(!d.leg[li].fvgFound && m_fvgMid >= d.leg[li].dispTime)
        {
         if(dir < 0 && m_barFvgBear)
            SetLegFvg(d.leg[li], m_bearTop, m_bearBot, t);
         else if(dir > 0 && m_barFvgBull)
            SetLegFvg(d.leg[li], m_bullTop, m_bullBot, t);
        }

      if(d.leg[li].mssLevel <= 0)
        {
         FailLeg(d, idx, li, DLS_FAIL_NO_MSS, t, c);   // no confirmed structure to shift
         return;
        }
      bool shifted = (dir < 0) ? (c < d.leg[li].mssLevel) : (c > d.leg[li].mssLevel);
      if(shifted)
        {
         d.leg[li].mssTime = t;
         Commit(d, idx, li, t);
         return;
        }
      if(!dispBar && ((dir < 0) ? (c > d.leg[li].sweepExtreme) : (c < d.leg[li].sweepExtreme)))
        {
         FailLeg(d, idx, li, DLS_FAIL_STRUCTURE, t, c);
         return;
        }
      if(d.leg[li].barsSinceDisp >= s.mssMaxBars)
         FailLeg(d, idx, li, DLS_FAIL_NO_MSS, t, c);
     }

   void              SetLegFvg(SDlsLeg &lg, const double top, const double bot, const datetime t)
     {
      lg.fvgFound = true;
      lg.fvgTop = top;
      lg.fvgBottom = bot;
      lg.fvgTime = m_fvgMid;
      lg.fvgFormTime = t;
     }

   //--- MSS confirmed: the story now has a direction --------------------
   void              Commit(SDlsDay &d, const int idx, const int li, const datetime t)
     {
      d.leg[li].stage = DLS_LEG_COMMITTED;
      int other = 1 - li;
      if(LegActive(d.leg[other]))
         d.leg[other].stage = DLS_LEG_CANCELLED;
      d.bothSidesActive = false;
      d.committed = true;
      d.story = d.leg[li];
      d.storyAtr = m_atrPrev;
      d.fMss = true;
      d.sbSweep = InSilverBullet(d.story.sweepTime);
      d.sbDisp  = InSilverBullet(d.story.dispTime);
      d.sbMss   = InSilverBullet(t);
      int dir = d.story.dir;
      d.fModelMatch =
         (dir < 0 && d.londonStory == DLS_LS_SWEPT_ASIA_LOW  && (d.story.sweptMask & (1 << DLS_LV_LONDON_HIGH)) != 0) ||
         (dir > 0 && d.londonStory == DLS_LS_SWEPT_ASIA_HIGH && (d.story.sweptMask & (1 << DLS_LV_LONDON_LOW)) != 0);
      AddEvent(idx, t, d.story.mssLevel, DLS_EV_MSS, dir, d.story.levelKind, DLS_SES_NY, 0);
      d.transient = DLS_MSS_CONFIRMED;

      if(d.story.fvgFound && !s.fvgAfterMssOnly)
         ConfirmFvg(d, idx, t);
      else
        {
         d.story.fvgFound = false;
         d.storyStage = DLS_ST_WAIT_FVG;
         d.barsWaitFvg = 0;
        }
     }

   void              ConfirmFvg(SDlsDay &d, const int idx, const datetime t)
     {
      d.storyStage = DLS_ST_WAIT_RETRACE;
      d.fvgConfirmTime = t;
      d.fFvg = true;
      d.sbFvg = InSilverBullet(d.story.fvgFormTime);
      MarkStoryFvg(d.story.dir, d.story.fvgTime);
      AddEvent(idx, d.story.fvgTime, (d.story.fvgTop + d.story.fvgBottom) * 0.5, DLS_EV_STORY_FVG, d.story.dir, d.story.levelKind, DLS_SES_NY, 0);
      if(d.transient != DLS_MSS_CONFIRMED)
         d.transient = DLS_FVG_CONFIRMED;
     }

   void              StepStory(SDlsDay &d, const int idx, const datetime t, const double h, const double l, const double c)
     {
      int dir = d.story.dir;
      if(t == d.story.mssTime)
         return;

      if(d.storyStage == DLS_ST_WAIT_FVG || d.storyStage == DLS_ST_WAIT_RETRACE)
        {
         if(d.nyCutoffDone)
            return;
         // structure continues against the story: invalidated
         if((dir < 0) ? (c > d.story.sweepExtreme) : (c < d.story.sweepExtreme))
           {
            d.storyStage = DLS_ST_INVALIDATED;
            d.fInvalid = true;
            d.invalidTime = t;
            AddEvent(idx, t, c, DLS_EV_INVALIDATED, dir, d.story.levelKind, DLS_SES_NY, 0);
            return;
           }
        }

      if(d.storyStage == DLS_ST_WAIT_FVG)
        {
         d.barsWaitFvg++;
         bool found = false;
         if(m_fvgMid >= d.story.dispTime)
           {
            if(dir < 0 && m_barFvgBear) { SetLegFvg(d.story, m_bearTop, m_bearBot, t); found = true; }
            if(dir > 0 && m_barFvgBull) { SetLegFvg(d.story, m_bullTop, m_bullBot, t); found = true; }
           }
         if(found)
            ConfirmFvg(d, idx, t);
         else if(d.barsWaitFvg >= s.fvgMaxBars)
           {
            d.storyStage = DLS_ST_NO_FVG;
            AddEvent(idx, t, c, DLS_EV_STORY_STALLED, dir, d.story.levelKind, DLS_SES_NY, DLS_ST_NO_FVG);
           }
         return;
        }

      if(d.storyStage == DLS_ST_WAIT_RETRACE)
        {
         if(t <= d.fvgConfirmTime)
            return;
         double lvl = RetraceLevelOf(d.story);
         bool touched = (dir < 0) ? (h >= lvl) : (l <= lvl);
         if(!touched)
            return;
         d.storyStage = DLS_ST_COMPLETE;
         d.retraceTime = t;
         d.retracePrice = lvl;
         d.fRetrace = true;
         d.fComplete = true;
         // intrabar order unknown: retrace bar counts for adverse side, close for favourable side
         d.mae = (dir < 0) ? MathMax(0.0, h - lvl) : MathMax(0.0, lvl - l);
         d.mfe = (dir < 0) ? MathMax(0.0, lvl - c) : MathMax(0.0, c - lvl);
         AddEvent(idx, t, lvl, DLS_EV_RETRACE, dir, d.story.levelKind, DLS_SES_NY, 0);
         return;
        }

      if(d.storyStage == DLS_ST_COMPLETE && !d.evalDone && t > d.retraceTime)
        {
         double lvl = d.retracePrice;
         if(dir < 0)
           {
            d.mfe = MathMax(d.mfe, lvl - l);
            d.mae = MathMax(d.mae, h - lvl);
           }
         else
           {
            d.mfe = MathMax(d.mfe, h - lvl);
            d.mae = MathMax(d.mae, lvl - l);
           }
        }
     }

   //--- development cutoff: pending legs / stages end here -------------
   void              CutoffNy(SDlsDay &d, const int idx, const datetime t)
     {
      d.nyCutoffDone = true;
      d.nyWindowClosed = true;
      if(!d.committed)
        {
         for(int li = 0; li < 2; li++)
            if(LegActive(d.leg[li]))
               FailLeg(d, idx, li, DLS_FAIL_CUTOFF, t, d.leg[li].levelPrice);
         d.bothSidesActive = false;
         return;
        }
      if(d.storyStage == DLS_ST_WAIT_FVG)
        {
         d.storyStage = DLS_ST_NO_FVG;
         AddEvent(idx, t, d.story.mssLevel, DLS_EV_STORY_STALLED, d.story.dir, d.story.levelKind, DLS_SES_NY, DLS_ST_NO_FVG);
        }
      else if(d.storyStage == DLS_ST_WAIT_RETRACE)
        {
         d.storyStage = DLS_ST_NO_RETRACE;
         AddEvent(idx, t, RetraceLevelOf(d.story), DLS_EV_STORY_STALLED, d.story.dir, d.story.levelKind, DLS_SES_NY, DLS_ST_NO_RETRACE);
        }
     }

   int               DeriveState(const SDlsDay &d, const int sm) const
     {
      if(!d.asiaStarted && !d.lonStarted && !d.nyStarted)
         return DLS_DAY_START;
      if(d.asiaStarted && !d.asiaLocked)
         return DLS_ASIA_BUILDING;
      if(!d.lonStarted && !d.nyStarted)
         return DLS_WAIT_LONDON;
      if(d.lonStarted && !d.lonLocked)
        {
         bool raided = d.lv[DLS_LV_ASIA_HIGH].takenBy == DLS_SES_LONDON || d.lv[DLS_LV_ASIA_LOW].takenBy == DLS_SES_LONDON;
         return raided ? DLS_LONDON_BUILDING_LIQUIDITY : DLS_LONDON_MONITORING_ASIA;
        }
      if(!d.nyStarted)
         return (sm >= m_nS) ? DLS_NY_NO_SWEEP : DLS_WAIT_NEW_YORK;

      if(d.committed)
        {
         switch(d.storyStage)
           {
            case DLS_ST_WAIT_FVG:     return DLS_WAIT_FVG;
            case DLS_ST_WAIT_RETRACE: return DLS_WAIT_RETRACE;
            case DLS_ST_COMPLETE:     return DLS_STORY_COMPLETE;
            case DLS_ST_INVALIDATED:  return DLS_STORY_INVALIDATED;
            case DLS_ST_NO_FVG:       return DLS_NO_STORY_FVG;
            case DLS_ST_NO_RETRACE:   return DLS_NO_RETRACE;
           }
         return DLS_MSS_CONFIRMED;
        }
      bool a0 = LegActive(d.leg[0]), a1 = LegActive(d.leg[1]);
      if(a0 && a1)
         return DLS_NY_BOTH_SIDES_TAKEN;
      if(a0 || a1)
        {
         int st = a0 ? d.leg[0].stage : d.leg[1].stage;
         return (st == DLS_LEG_WAIT_DISP) ? DLS_WAIT_DISPLACEMENT : DLS_WAIT_MSS;
        }
      if(d.fNoReversal)
         return DLS_NY_NO_REVERSAL;
      if(d.nyWindowClosed)
         return DLS_NY_NO_SWEEP;
      return DLS_NY_MONITORING_LIQUIDITY;
     }
  };

#endif
//+------------------------------------------------------------------+

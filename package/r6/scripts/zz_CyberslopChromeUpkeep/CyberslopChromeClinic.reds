// Cyberslop Chrome Upkeep: the ripperdoc visit (2026-11-06)
// 1.6.1 (2026-11-22): after each clock skip (desk repair, checkout) ChromeWear.SettleAfterSkip charges the chair
//   time's drift, then keeps the restored systems at their restored value (was 99.5 % after a long repair).
// 1.6.0 (2026-11-22): repairs (clinic desk and chair service) use the components in V's bag first and charge
//   only for the missing ones (setting repairUsesBag); one plan (PlanRepairs) for Repair all, the chair service and
//   the window's total, so the bag and the money are shared worst system first.
// 1.5.0 (2026-11-20): the chair service uses ChromeRepair's quote (materials + fee, to 100 % at every clinic);
//   the clinic desk for the Cyberslop Chrome Clinic CET window: a ripperdoc within 4 m (or the one whose menu V
//   opened, within 6 m) repairs any system, sells nanobot canisters. Vendor names localized in the log and bill.
// 1.4.0 (2026-11-17, game 2.5 port): RipperDocGameController.UnequipCyberware takes `opt itemToEquip` in 2.5;
// Dark Future 3.0's time-skip forecast takes the starting hour and carries biocorruption data.
// A visit = from opening a ripperdoc's menu to leaving it. If V sat in the chair (the cyberware
// screen was open), checkout happens a moment after leaving:
//   1. Trauma care (Injuries mod): every injury treated, Injuries doctor price and time.
//   2. Service: worn systems back to 100 %, cost = ChromeRepair.Quote (materials + fee), worst first,
//      as far as V can pay; 10 min + 0.3 min per % of wear each (+5 min per extra implant).
//   3. Surgery: each implant installed (or removed) this visit is an operation:
//      cortex 2 h, operating system 4 h, optics 1 h, circulatory 2.5 h, nervous 3 h, skin 2 h,
//      immune 1 h, skeleton 4 h, arms 3 h, hands 1 h, legs 2.5 h; the next ones in the same
//      session take 60 %, removals 40 %, self-install with a RipperDeck 150 %. Max 16 h.
//      Real reference: enucleation + prosthesis ~1 h, pacemaker 1-2 h, joint replacement 2-3 h,
//      spinal fusion 3-6 h. Systems operated on are checked over too (condition 100 %).
//   4. The clock jumps by the total (Dark Future needs follow, via its own time-skip events).
//   5. Recovery: operated regions heal like a light injury (Injuries: neural fog for head work,
//      stiff arms, limp; 4 h+ in one region = tier 2; sleep or 10-12 game h clear it), and
//      stamina regenerates 25 % slower for 3x the surgery time.
// One bill on the HUD. Payments are tagged for Cyberslop Cashflow.
// 1.2.0 (2026-11-06): clinic quality. The ripper's tier from Cyberslop Ripper Stock (top: Viktor, Nina Kraviz,
// Darius Clarke...; pro: Robert Rainwater, Cassius Ryder...; street: everyone else) changes the visit:
//   surgery time x1.25 / 1.0 / 0.85 (fewer hands, older tools vs a full team),
//   service price x0.8 / 1.0 / 1.3 (1.5.0: fee x0.75 / 1.0 / 1.3, every clinic repairs to 100 %),
//   complications 8 % / 3 % / 1 % per procedure, RipperDeck self-install 10 %, doubled while the last surgery's
//   recovery is still running (operating on a body that has not healed). Reference: surgical site infection
//   2-5 % in general surgery, two to three times that in low-resource settings; reoperation within weeks raises it.
//   A complication = the implant out of calibration (condition 80 %) and 4 h more recovery in its region
//   (the chest: 12 h more fatigue). Tiers: a copy of Ripper Stock's table (CCU_RipperTier).
// 1.2.1 (2026-11-06, review): a complication on a removal no longer sets the condition of an empty system to
//   80 % (only the recovery penalty applies); a load drops an unfinished visit instead of charging it to the
//   loaded save.
module CyberslopChromeUpkeep

@if(ModuleExists("Injuries"))
import Injuries.*
@if(ModuleExists("DarkFuture.Main"))
import DarkFuture.Main.*
@if(ModuleExists("DarkFuture.Gameplay"))
import DarkFuture.Gameplay.*
@if(ModuleExists("CyberslopCashflow"))
import CyberslopCashflow.*
@if(ModuleExists("TraumaTeam.System"))
import TraumaTeam.System.*

// ---------------------------------------------------------------- optional bridges

// 0 street, 1 pro, 2 top. A copy of Cyberslop Ripper Stock 1.0.0's CyberslopRipperTier table (module-private
// there; it mirrors Ripperdoc Service Charge's quality caps). Keep both in step.
func CCU_RipperTier(id: TweakDBID) -> Int32 {
  switch id {
    case t"Vendors.cct_dtn_ripdoc_01":              // Darius Clarke, City Center
    case t"Vendors.cz_monument_ripperdoc_farida":   // Farida Nazeri, Dogtown
    case t"Vendors.cz_stadium_ripperdoc_01":        // Eron Acedo, Dogtown black market
    case t"Vendors.pac_wwd_ripperdoc_01":           // Pacifica, West Wind
    case t"Vendors.wat_kab_ripperdoc_02":           // Charles Bucks, Kabuki
    case t"Vendors.wat_lch_ripperdoc_01":           // Viktor, Little China
    case t"Vendors.wbr_jpn_ripperdoc_01":           // Japantown, Cherry Blossom Market
    case t"Vendors.wbr_hil_ripdoc_01":              // Nina Kraviz, Charter Hill
      return 2;
    case t"Vendors.bls_ina_se1_ripperdoc_01":       // Badlands camp
    case t"Vendors.cz_con_ripdoc_01":               // Costin, Dogtown
    case t"Vendors.hey_spr_ripperdoc_01":           // Heywood
    case t"Vendors.std_arr_ripperdoc_01":           // Arroyo
    case t"Vendors.wat_kab_ripperdoc_03":           // Robert Rainwater, Kabuki
    case t"Vendors.wat_nid_ripperdoc_01":           // Cassius Ryder, Northside
      return 1;
  };
  return 0;
}

// Trauma Team International plan pays its share of trauma care (not elective chrome work).
// Shares = US health-plan actuarial values: Silver 70 %, Gold 80 %, Platinum 90 %.
@if(ModuleExists("TraumaTeam.System"))
func CCU_TTCoverage(player: ref<PlayerPuppet>) -> Float {
  let tt: ref<TraumaTeamSystem> = TraumaTeamSystem.GetInstance(player);
  let tier: Int32;
  if !IsDefined(tt) || !tt.IsActive() {
    return 0.0;
  };
  tier = tt.GetTier();
  if tier >= 3 { return 0.9; };
  if tier == 2 { return 0.8; };
  if tier == 1 { return 0.7; };
  return 0.0;
}
@if(!ModuleExists("TraumaTeam.System"))
func CCU_TTCoverage(player: ref<PlayerPuppet>) -> Float { return 0.0; }

@if(ModuleExists("Injuries"))
func CCU_InjuryCount(gi: GameInstance) -> Int32 {
  let sys: ref<InjuriesSystem> = InjuriesSystem.Get(gi);
  let cfg: ref<InjuriesConfig> = InjuriesConfig.Get();
  if !IsDefined(sys) || !IsDefined(cfg) || !cfg.modON || !sys.IsLive() {
    return 0;
  };
  return sys.GetInjuryCount();
}
@if(!ModuleExists("Injuries"))
func CCU_InjuryCount(gi: GameInstance) -> Int32 { return 0; }

@if(ModuleExists("Injuries"))
func CCU_TraumaCost(count: Int32) -> Int32 { return DoctorCostForCount(count); }
@if(!ModuleExists("Injuries"))
func CCU_TraumaCost(count: Int32) -> Int32 { return 0; }

@if(ModuleExists("Injuries"))
func CCU_TraumaMinutes(count: Int32) -> Int32 {
  let mult: Float = 1.0;
  if count == 2 { mult = 1.5; };
  if count >= 3 { mult = 2.0; };
  return Cast<Int32>(Cast<Float>(DoctorBaseVisitSec()) * mult / 60.0);
}
@if(!ModuleExists("Injuries"))
func CCU_TraumaMinutes(count: Int32) -> Int32 { return 0; }

@if(ModuleExists("Injuries"))
func CCU_TraumaClear(gi: GameInstance) -> Void {
  let sys: ref<InjuriesSystem> = InjuriesSystem.Get(gi);
  if IsDefined(sys) {
    sys.ClearAll();
  };
}
@if(!ModuleExists("Injuries"))
func CCU_TraumaClear(gi: GameInstance) -> Void {}

// Injuries regions: 0 head, 1 torso, 2 left arm, 3 right arm, 4 left leg, 5 right leg.
@if(ModuleExists("Injuries"))
func CCU_PostOp(gi: GameInstance, region: Int32, tier: Int32) -> Bool {
  let sys: ref<InjuriesSystem> = InjuriesSystem.Get(gi);
  let cfg: ref<InjuriesConfig> = InjuriesConfig.Get();
  if !IsDefined(sys) || !IsDefined(cfg) || !cfg.modON || !sys.IsLive() {
    return false;
  };
  if sys.GetSeverity(region) < tier {
    sys.SetSeverity(region, tier);
  };
  return true;
}
@if(!ModuleExists("Injuries"))
func CCU_PostOp(gi: GameInstance, region: Int32, tier: Int32) -> Bool { return false; }

// Time skip that keeps Dark Future's needs consistent (its own wait-screen events).
@if(ModuleExists("DarkFuture.Gameplay"))
func CCU_SkipTime(gi: GameInstance, seconds: Int32) -> Void {
  let ts: ref<TimeSystem> = GameInstance.GetTimeSystem(gi);
  let hours: Int32 = seconds / 3600;
  let main: ref<DFMainSystem> = DFMainSystem.GetInstance(gi);
  let inter: ref<DFInteractionSystem> = DFInteractionSystem.GetInstance(gi);
  let data: DFFutureHoursData;
  let tsd: DFTimeSkipData;
  if hours > 24 {
    hours = 24;
  };
  if hours >= 1 && IsDefined(main) && IsDefined(inter) {
    data = inter.GetCalculatedValuesForFutureHours(DFTimeSkipType.TimeSkip, GameTime.Hours(ts.GetGameTime()));
    if ArraySize(data.futureNeedsData) >= hours && ArraySize(data.futureAddictionData) >= hours && ArraySize(data.futureHumanityLossData) >= hours && ArraySize(data.futureBiocorruptionData) >= hours {
      main.DispatchTimeSkipStartEvent();
      ts.SetGameTimeBySeconds(Cast<Int32>(ts.GetGameTimeStamp()) + seconds);
      tsd.hoursSkipped = hours;
      tsd.targetNeedValues = data.futureNeedsData[hours - 1];
      tsd.targetAddictionValues = data.futureAddictionData[hours - 1];
      tsd.targetHumanityLossValues = data.futureHumanityLossData[hours - 1];
      // 2.5 port: Dark Future 3.0 also carries its biocorruption state through a time skip
      tsd.targetBiocorruptionValues = data.futureBiocorruptionData[hours - 1];
      tsd.timeSkipType = DFTimeSkipType.TimeSkip;
      main.DispatchTimeSkipFinishedEvent(tsd);
      return;
    };
  };
  ts.SetGameTimeBySeconds(Cast<Int32>(ts.GetGameTimeStamp()) + seconds);
}
@if(!ModuleExists("DarkFuture.Gameplay"))
func CCU_SkipTime(gi: GameInstance, seconds: Int32) -> Void {
  let ts: ref<TimeSystem> = GameInstance.GetTimeSystem(gi);
  ts.SetGameTimeBySeconds(Cast<Int32>(ts.GetGameTimeStamp()) + seconds);
}

@if(ModuleExists("CyberslopCashflow"))
func CCU_Tag(gi: GameInstance, medical: Bool, detail: String) -> Void {
  CashflowBook.TagNow(gi, medical ? CashflowCat.Medical() : CashflowCat.Chrome(), detail, 3.0);
}
@if(!ModuleExists("CyberslopCashflow"))
func CCU_Tag(gi: GameInstance, medical: Bool, detail: String) -> Void {}

// ---------------------------------------------------------------- the clinic

public class ChromeClinicCheckout extends DelayCallback {
  public let sys: wref<ChromeClinic>;
  public let gen: Int32;
  public func Call() -> Void {
    if IsDefined(this.sys) {
      this.sys.Checkout(this.gen);
    };
  }
}

public class ChromeClinicTick extends DelayCallback {
  public let sys: wref<ChromeClinic>;
  public let gen: Int32;
  public func Call() -> Void {
    if IsDefined(this.sys) {
      this.sys.Tick(this.gen);
    };
  }
}

public class ChromeClinicGlitchOff extends DelayCallback {
  public let player: wref<PlayerPuppet>;
  public func Call() -> Void {
    if IsDefined(this.player) {
      GameObjectEffectHelper.StopEffectEvent(this.player, n"time_skip_glitch");
    };
  }
}

public class ChromeClinic extends ScriptableSystem {

  // Post-op fatigue until this game time (kept in the save).
  public persistent let postOpUntil: Float;

  private let m_player: wref<PlayerPuppet>;
  private let m_open: Bool;
  private let m_deck: Bool;
  private let m_hub: Bool;
  private let m_chair: Bool;
  private let m_chairPending: Bool;
  private let m_vendor: String;
  private let m_tier: Int32;
  private let m_installs: array<Int32>;
  private let m_removals: array<Int32>;
  private let m_inEquip: Bool;
  private let m_gen: Int32;
  private let m_tickGen: Int32;
  private let m_postOpMods: array<ref<gameStatModifierData>>;
  // 1.3.0: trauma care bought with the Treat injuries button, billed (time + bill line) at checkout.
  private let m_traumaPaid: Int32;
  private let m_traumaMin: Float;
  private let m_traumaPart: String;
  // 1.5.0: the visit's vendor (Viktor's friend rate), the clinic desk the CET window talks to, and the last
  // ripper whose menu V opened (fallback when the targeting search misses a ripper at a workspot).
  private let m_vendorID: TweakDBID;
  private let m_deskNear: Bool;
  private let m_deskVendor: TweakDBID;
  private let m_deskName: String;
  private let m_deskTier: Int32;
  private let m_deskFriend: Bool;
  private let m_hubSet: Bool;
  private let m_hubPos: Vector4;
  private let m_hubVendor: TweakDBID;

  public static func Get(gi: GameInstance) -> ref<ChromeClinic> {
    return GameInstance.GetScriptableSystemsContainer(gi).Get(n"CyberslopChromeUpkeep.ChromeClinic") as ChromeClinic;
  }

  private final func Settings() -> ref<ChromeUpkeepSettings> {
    return ChromeUpkeepSettings.Get(this.GetGameInstance());
  }

  private final func Wear() -> ref<ChromeWear> {
    return ChromeWear.Get(this.GetGameInstance());
  }

  private final func Log(msg: String) -> Void {
    let w: ref<ChromeWear> = this.Wear();
    if IsDefined(w) {
      w.Log(msg);
    };
  }

  private final func GameNow() -> Float {
    return GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTimeStamp();
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.m_player = GameInstance.GetPlayerSystem(request.owner.GetGame()).GetLocalPlayerMainGameObject() as PlayerPuppet;
    this.m_open = false;
    this.m_inEquip = false;
    this.m_chairPending = false;
    ArrayClear(this.m_installs);
    ArrayClear(this.m_removals);
    ArrayClear(this.m_postOpMods);
    this.ClearTrauma();
    // A checkout queued before a load (End, then a load within 2.5 s) must not bill the loaded save.
    this.m_gen += 1;
    this.m_tickGen += 1;
    this.ScheduleTick(4.0);
  }

  private final func ScheduleTick(delay: Float) -> Void {
    let cb: ref<ChromeClinicTick> = new ChromeClinicTick();
    cb.sys = this;
    cb.gen = this.m_tickGen;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, delay, false);
  }

  // Post-op fatigue: put the modifier back after a load, take it off when it runs out.
  public final func Tick(gen: Int32) -> Void {
    let active: Bool;
    if gen != this.m_tickGen {
      return;
    };
    active = this.postOpUntil > 0.0 && this.GameNow() < this.postOpUntil;
    if active && ArraySize(this.m_postOpMods) == 0 {
      this.ApplyFatigue();
    };
    if !active && ArraySize(this.m_postOpMods) > 0 {
      this.ClearFatigue();
      this.postOpUntil = 0.0;
      this.Log("post-op recovery over");
    };
    this.ScheduleTick(60.0);
  }

  private final func ApplyFatigue() -> Void {
    let m: ref<gameStatModifierData>;
    if !IsDefined(this.m_player) {
      return;
    };
    m = RPGManager.CreateStatModifier(gamedataStatType.StaminaRegenRate, gameStatModifierType.Multiplier, 0.75);
    if GameInstance.GetStatsSystem(this.GetGameInstance()).AddModifier(Cast<StatsObjectID>(this.m_player.GetEntityID()), m) {
      ArrayPush(this.m_postOpMods, m);
    };
  }

  private final func ClearFatigue() -> Void {
    let i: Int32 = 0;
    if IsDefined(this.m_player) {
      while i < ArraySize(this.m_postOpMods) {
        GameInstance.GetStatsSystem(this.GetGameInstance()).RemoveModifier(Cast<StatsObjectID>(this.m_player.GetEntityID()), this.m_postOpMods[i]);
        i += 1;
      };
    };
    ArrayClear(this.m_postOpMods);
  }

  // --- visit

  public final func Begin(vendor: String, deck: Bool) -> Void {
    if this.m_open {
      return;
    };
    this.m_open = true;
    this.m_hub = false;
    this.m_deck = deck;
    this.m_chair = deck || this.m_chairPending;
    this.m_chairPending = false;
    this.m_vendor = deck ? "RipperDeck (self-install)" : vendor;
    this.m_tier = 1;
    this.m_vendorID = TDBID.None();
    ArrayClear(this.m_installs);
    ArrayClear(this.m_removals);
    this.ClearTrauma();
  }

  private final func ClearTrauma() -> Void {
    this.m_traumaPaid = 0;
    this.m_traumaMin = 0.0;
    this.m_traumaPart = "";
  }

  // --- 1.3.0: Treat injuries button in the cyberware screen

  public final func TraumaButtonOn() -> Bool {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    return IsDefined(s) && s.traumaCare && s.traumaButton;
  }

  public final func TraumaCount() -> Int32 {
    return CCU_InjuryCount(this.GetGameInstance());
  }

  // What V pays: the Injuries doctor price minus the Trauma Team share.
  public final func TraumaCost(count: Int32) -> Int32 {
    let c: Float = CCU_TTCoverage(this.m_player);
    return Cast<Int32>(Cast<Float>(CCU_TraumaCost(count)) * (1.0 - c));
  }

  // 0 treated, 1 nothing to treat, 2 not enough money.
  public final func TreatNow(vendor: String) -> Int32 {
    let gi: GameInstance = this.GetGameInstance();
    let count: Int32 = CCU_InjuryCount(gi);
    let c: Float;
    let bill: Int32;
    let cost: Int32;
    if count <= 0 || !IsDefined(this.m_player) {
      return 1;
    };
    c = CCU_TTCoverage(this.m_player);
    bill = CCU_TraumaCost(count);
    cost = Cast<Int32>(Cast<Float>(bill) * (1.0 - c));
    if !this.Pay(cost, true, "trauma care") {
      this.Log("trauma care button: refused, " + IntToString(cost) + " eb needed");
      return 2;
    };
    CCU_TraumaClear(gi);
    // A ripper screen without the vendor hub: open the visit here so checkout bills the time.
    if !this.m_open {
      this.Begin(vendor, false);
    };
    this.m_chair = true;
    this.m_traumaPaid += cost;
    this.m_traumaMin += Cast<Float>(CCU_TraumaMinutes(count));
    this.m_traumaPart += " · trauma care " + ChromeClinic.Eddies(cost) + " (" + IntToString(count) + (count == 1 ? " injury" : " injuries") + (c > 0.0 ? ", Trauma Team paid " + IntToString(Cast<Int32>(c * 100.0)) + " %)" : ")");
    this.Log("trauma care button: " + IntToString(count) + " injuries, bill " + IntToString(bill) + " eb, TT share " + FloatToStringPrec(c, 2) + ", V paid " + IntToString(cost) + " eb");
    return 0;
  }

  // A visit opened by the vendor hub ends with the hub; any other (RipperDeck, a ripper without
  // the hub) ends with the cyberware screen.
  public final func BeginFromHub(vendor: String, opt tier: Int32) -> Void {
    this.Begin(vendor, false);
    this.m_hub = true;
    this.m_tier = Max(0, Min(2, tier));
  }

  // 1.5.0: the hub's vendor: Viktor's rate in the chair, and the desk fallback (this ripper counts as near
  // while V stays within 6 m of where they stood).
  public final func NoteHub(vendorObj: wref<GameObject>, id: TweakDBID) -> Void {
    this.m_vendorID = id;
    if IsDefined(vendorObj) {
      this.m_hubSet = true;
      this.m_hubPos = vendorObj.GetWorldPosition();
      this.m_hubVendor = id;
    };
  }

  private final static func TierName(tier: Int32) -> String {
    if tier <= 0 { return "street clinic"; };
    if tier >= 2 { return "top clinic"; };
    return "clinic";
  }

  // The cyberware tab can initialize before the hub's user data arrives.
  public final func SatInChair() -> Void {
    if this.m_open {
      this.m_chair = true;
    } else {
      this.m_chairPending = true;
    };
  }

  public final func EndsWithScreen() -> Bool = this.m_open && !this.m_hub

  public final func SetInEquip(b: Bool) -> Void {
    this.m_inEquip = b;
  }

  public final func NoteInstall(area: gamedataEquipmentArea, deck: Bool) -> Void {
    let a: Int32 = ChromeArea.FromEquipmentArea(area);
    if !this.m_open {
      this.Begin("", deck);
    };
    if a >= 0 {
      ArrayPush(this.m_installs, a);
    };
  }

  public final func NoteRemoval(area: gamedataEquipmentArea, deck: Bool) -> Void {
    let a: Int32 = ChromeArea.FromEquipmentArea(area);
    if this.m_inEquip {
      return;
    };
    if !this.m_open {
      this.Begin("", deck);
    };
    if a >= 0 {
      ArrayPush(this.m_removals, a);
    };
  }

  public final func End() -> Void {
    let cb: ref<ChromeClinicCheckout>;
    if !this.m_open {
      return;
    };
    this.m_gen += 1;
    cb = new ChromeClinicCheckout();
    cb.sys = this;
    cb.gen = this.m_gen;
    // Let the menu close and the install animation start first.
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 2.5, false);
  }

  // --- pricing

  public final static func SurgeryBase(a: Int32) -> Float {
    switch a {
      case 0: return 120.0;
      case 1: return 240.0;
      case 2: return 60.0;
      case 3: return 150.0;
      case 4: return 180.0;
      case 5: return 120.0;
      case 6: return 60.0;
      case 7: return 240.0;
      case 8: return 180.0;
      case 9: return 60.0;
      case 10: return 150.0;
    };
    return 60.0;
  }

  // Price of the parts installed in one body system (what V would pay for them today).
  // --- 1.5.0: the clinic desk (Cyberslop Chrome Clinic CET window)

  public final static func VendorName(id: TweakDBID) -> String {
    let rec: ref<Vendor_Record> = TweakDBInterface.GetVendorRecord(id);
    let name: String;
    if IsDefined(rec) {
      name = GetLocalizedText(rec.LocalizedName());
      if StrLen(name) > 0 && !StrBeginsWith(name, "LocKey") {
        return name;
      };
    };
    return "Ripperdoc";
  }

  // Is a ripperdoc within reach? Living, not hostile, within 4 m; or the ripper whose menu V opened last, within 6 m.
  public final func DeskUpdate() -> Bool {
    let player: ref<PlayerPuppet> = this.m_player;
    let npcs: array<ref<NPCPuppet>>;
    let pos: Vector4;
    let id: TweakDBID;
    let best: Float = 100.0;
    let d: Float;
    let found: Bool = false;
    let i: Int32 = 0;
    this.m_deskNear = false;
    if !IsDefined(player) {
      return false;
    };
    pos = player.GetWorldPosition();
    npcs = player.GetNPCsAroundObject(4.0);
    while i < ArraySize(npcs) {
      if IsDefined(npcs[i]) && npcs[i].IsRipperdoc() && !npcs[i].IsDead() && !npcs[i].IsHostile() {
        d = Vector4.Distance(pos, npcs[i].GetWorldPosition());
        if d < best {
          best = d;
          id = MarketSystem.GetVendorID(npcs[i]);
          found = TDBID.IsValid(id);
        };
      };
      i += 1;
    };
    if !found && this.m_hubSet && TDBID.IsValid(this.m_hubVendor) && Vector4.Distance(pos, this.m_hubPos) < 6.0 {
      id = this.m_hubVendor;
      found = true;
    };
    if found {
      this.m_deskNear = true;
      if NotEquals(id, this.m_deskVendor) || StrLen(this.m_deskName) == 0 {
        this.m_deskVendor = id;
        this.m_deskTier = CCU_RipperTier(id);
        this.m_deskFriend = Equals(id, ChromeRepair.Viktor());
        this.m_deskName = ChromeClinic.VendorName(id);
      };
    };
    return this.m_deskNear;
  }

  public final func DeskNear() -> Bool = this.m_deskNear
  public final func DeskName() -> String = this.m_deskName
  public final func DeskTier() -> Int32 = this.m_deskTier
  public final func DeskFriend() -> Bool = this.m_deskFriend
  public final func DeskTierName() -> String = ChromeClinic.TierName(this.m_deskTier)

  public final func Money() -> Int32 {
    if !IsDefined(this.m_player) {
      return 0;
    };
    return GameInstance.GetTransactionSystem(this.GetGameInstance()).GetItemQuantity(this.m_player, MarketSystem.Money());
  }

  public final func InCombat() -> Bool = IsDefined(this.m_player) && this.m_player.IsInCombat()

  public final func StreetCred() -> Int32 = ChromeRepair.StreetCred(this.GetGameInstance(), this.m_player)

  // 1.6.0: the components the ripper may use, per quality (setting off or no player: none).
  public final func Bag() -> array<Int32> {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let none: array<Int32>;
    if !IsDefined(this.m_player) || (IsDefined(s) && !s.repairUsesBag) {
      return none;
    };
    return ChromeRepair.Inventory(this.GetGameInstance(), this.m_player);
  }

  public final func UsesBag() -> Bool {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    return !IsDefined(s) || s.repairUsesBag;
  }

  // "12 Legendary, 30 Rare" in V's bag (all qualities, whether or not the setting is on).
  public final func BagText() -> String {
    if !IsDefined(this.m_player) {
      return "none";
    };
    return ChromeRepair.UnitsText(ChromeRepair.Inventory(this.GetGameInstance(), this.m_player));
  }

  // Quote for system a at the ripper in reach (none in reach: a pro clinic's price, as an estimate), on V's whole bag.
  public final func Quote(a: Int32) -> ref<ChromeQuote> {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let w: ref<ChromeWear> = this.Wear();
    let near: Bool = this.m_deskNear;
    return ChromeRepair.Quote(this.GetGameInstance(), this.m_player, a, IsDefined(w) ? w.Condition(a) : 100.0, near ? this.m_deskTier : 1, near && this.m_deskFriend, IsDefined(s) ? s.repairPricePct : 100, this.Bag());
  }

  // 1.6.0: repairs in the order they are paid, worst first, sharing the bag and the money.
  //   only: one system (>= 0) or all (-1); minCond: systems below this (99.5 at the desk, 60 / 95 in the chair);
  //   money < 0 = unlimited (the "everything" estimate); tier / friend as the quote takes them.
  public final func PlanRepairs(only: Int32, minCond: Float, money: Int32, tier: Int32, friend: Bool) -> ref<ChromeRepairPlan> {
    let gi: GameInstance = this.GetGameInstance();
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let w: ref<ChromeWear> = this.Wear();
    let plan: ref<ChromeRepairPlan> = new ChromeRepairPlan();
    let bag: array<Int32> = this.Bag();
    let order: array<Int32>;
    let q: ref<ChromeQuote>;
    let a: Int32;
    let i: Int32;
    let j: Int32;
    let k: Int32 = 0;
    while k < 5 {
      ArrayPush(plan.own, 0);
      if ArraySize(bag) <= k {
        ArrayPush(bag, 0);
      };
      k += 1;
    };
    plan.ownText = "none";
    if !IsDefined(w) || !IsDefined(this.m_player) {
      return plan;
    };
    a = 0;
    while a < ChromeArea.Count() {
      if (only < 0 || only == a) && w.HasChrome(a) && w.Condition(a) < minCond {
        ArrayPush(order, a);
      };
      a += 1;
    };
    while ArraySize(order) > 0 {
      i = 0;
      j = 0;
      while i < ArraySize(order) {
        if w.Condition(order[i]) < w.Condition(order[j]) {
          j = i;
        };
        i += 1;
      };
      a = order[j];
      ArrayErase(order, j);
      q = ChromeRepair.Quote(gi, this.m_player, a, w.Condition(a), tier, friend, IsDefined(s) ? s.repairPricePct : 100, bag);
      if q.total > 0 {
        if money >= 0 && q.total > money {
          plan.skippedN += 1;
          plan.skipped += (StrLen(plan.skipped) > 0 ? ", " : "") + ChromeArea.Name(a) + " " + ChromeClinic.Eddies(q.total);
        } else {
          if money >= 0 {
            money -= q.total;
          };
          k = 0;
          while k < 5 {
            bag[k] = bag[k] - q.own[k];
            plan.own[k] = plan.own[k] + q.own[k];
            k += 1;
          };
          ArrayPush(plan.quotes, q);
          plan.count += 1;
          plan.total += q.total;
          plan.mat += q.mat;
          plan.fee += q.fee;
          plan.minutes += q.minutes;
          plan.ownValue += q.ownValue;
        };
      };
    };
    plan.ownN = ChromeRepair.UnitsSum(plan.own);
    plan.ownText = ChromeRepair.UnitsText(plan.own);
    return plan;
  }

  // For the CET window: everything below 100 % at the ripper in reach (or a pro clinic), money unlimited / V's money.
  public final func PlanAll() -> ref<ChromeRepairPlan> = this.PlanRepairs(-1, 99.5, -1, this.m_deskNear ? this.m_deskTier : 1, this.m_deskNear && this.m_deskFriend)
  public final func PlanAfford() -> ref<ChromeRepairPlan> = this.PlanRepairs(-1, 99.5, this.Money(), this.m_deskNear ? this.m_deskTier : 1, this.m_deskNear && this.m_deskFriend)

  // Repair one system (only >= 0) or every system below 100 % (only = -1), worst first, as far as V can pay.
  // 1.6.0: components from V's bag first, the missing ones bought (PlanRepairs).
  public final func DeskRepair(only: Int32) -> String {
    let gi: GameInstance = this.GetGameInstance();
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let w: ref<ChromeWear> = this.Wear();
    let plan: ref<ChromeRepairPlan>;
    let q: ref<ChromeQuote>;
    let fx: ref<ChromeClinicGlitchOff>;
    let a: Int32;
    let i: Int32;
    let k: Int32;
    let total: Int32 = 0;
    let mat: Int32 = 0;
    let fee: Int32 = 0;
    let minutes: Int32 = 0;
    let used: array<Int32>;
    let done: String = "";
    let skipped: String = "";
    let msg: String;
    if !IsDefined(s) || !IsDefined(w) || !IsDefined(this.m_player) {
      return "No player.";
    };
    if !this.DeskUpdate() {
      return "No ripperdoc in reach: stand next to one.";
    };
    if this.m_player.IsInCombat() {
      return "No ripper works on you in the middle of a fight.";
    };
    w.NanoUpdate();
    w.RefreshCounts();
    plan = this.PlanRepairs(only, 99.5, this.Money(), this.m_deskTier, this.m_deskFriend);
    if plan.count == 0 && plan.skippedN == 0 {
      return "Nothing to repair: every system is at 100 %.";
    };
    skipped = plan.skipped;
    i = 0;
    while i < 5 {
      ArrayPush(used, 0);
      i += 1;
    };
    i = 0;
    while i < ArraySize(plan.quotes) {
      q = plan.quotes[i];
      a = q.area;
      if this.Pay(q.total, false, "chrome repair " + ChromeArea.Name(a)) {
        if q.ownN > 0 && !ChromeRepair.Take(gi, this.m_player, q.own) {
          this.Log("desk repair " + ChromeArea.Name(a) + ": components from the bag short (" + q.ownText + "), repaired anyway");
        };
        this.Log("desk repair " + ChromeArea.Name(a) + " " + FloatToStringPrec(q.cond, 1) + " % -> 100 | components " + q.partsText + ", from the bag " + q.ownText + ", bought " + q.buyText + " = " + IntToString(q.mat) + " (all bought " + IntToString(q.matList) + ") + fee " + IntToString(q.fee) + " (list " + IntToString(q.feeList) + ", -" + IntToString(q.cut) + " %) = " + IntToString(q.total) + " eb | " + this.m_deskName + " " + ChromeClinic.TierName(this.m_deskTier));
        w.Restore(a, 100.0);
        total += q.total;
        mat += q.mat;
        fee += q.fee;
        minutes += q.minutes;
        k = 0;
        while k < 5 {
          used[k] = used[k] + q.own[k];
          k += 1;
        };
        done += (StrLen(done) > 0 ? ", " : "") + ChromeArea.Name(q.area) + " " + IntToString(Cast<Int32>(q.cond)) + "%";
      } else {
        skipped += (StrLen(skipped) > 0 ? ", " : "") + ChromeArea.Name(a) + " " + ChromeClinic.Eddies(q.total);
        this.Log("desk repair skipped " + ChromeArea.Name(a) + " " + FloatToStringPrec(q.cond, 1) + " % | " + IntToString(q.total) + " eb not affordable");
      };
      i += 1;
    };
    if StrLen(done) == 0 {
      msg = "Can't pay: " + skipped + " eddies.";
      return msg;
    };
    if minutes >= 1 {
      GameObjectEffectHelper.StartEffectEvent(this.m_player, n"time_skip_glitch", false);
      fx = new ChromeClinicGlitchOff();
      fx.player = this.m_player;
      GameInstance.GetDelaySystem(gi).DelayCallback(fx, 1.0, false);
      CCU_SkipTime(gi, minutes * 60);
    };
    // 1.6.1: chair-time drift settled now, repaired systems stay at 100 %.
    w.SettleAfterSkip();
    if plan.skippedN > 0 {
      this.Log("desk repair skipped (not affordable): " + plan.skipped);
    };
    w.UpdateTiers(false);
    msg = this.m_deskName + ": repaired " + done + " to 100 % · " + ChromeClinic.Eddies(total) + " eddies (materials " + ChromeClinic.Eddies(mat) + ", fee " + ChromeClinic.Eddies(fee) + ")" + (ChromeRepair.UnitsSum(used) > 0 ? " · from your bag: " + ChromeRepair.UnitsText(used) : "") + " · " + ChromeClinic.Clock(minutes) + " in the chair" + (StrLen(skipped) > 0 ? " · can't pay for " + skipped : "");
    if s.notices {
      w.Notice(msg, SimpleMessageType.Neutral);
    };
    return msg;
  }

  // Nanobot canisters, from the ripper in reach. Fixed price, no Street Cred haggling: it is a sealed medical product.
  public final func BuyNanobots(n: Int32) -> String {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let w: ref<ChromeWear> = this.Wear();
    let room: Int32;
    let cost: Int32;
    let msg: String;
    if !IsDefined(s) || !s.nanobots {
      return "Nanobot canisters are off (Mod Settings > Cyberslop Chrome Upkeep).";
    };
    if !IsDefined(w) || !IsDefined(this.m_player) {
      return "No player.";
    };
    if !this.DeskUpdate() {
      return "Nanobots are sold by ripperdocs: stand next to one.";
    };
    if this.m_player.IsInCombat() {
      return "Not in the middle of a fight.";
    };
    room = ChromeRepair.NanoCarry() - w.nanobots;
    if room <= 0 {
      return "You already carry " + IntToString(ChromeRepair.NanoCarry()) + " canisters.";
    };
    n = Max(1, Min(n, room));
    cost = n * ChromeRepair.NanoPrice();
    if !this.Pay(cost, false, "nanobot canisters") {
      return IntToString(n) + (n == 1 ? " canister costs " : " canisters cost ") + ChromeClinic.Eddies(cost) + " eddies, you have " + ChromeClinic.Eddies(this.Money()) + ".";
    };
    w.AddNanobots(n);
    msg = this.m_deskName + ": " + IntToString(n) + " nanobot " + (n == 1 ? "canister" : "canisters") + " for " + ChromeClinic.Eddies(cost) + " eddies. You carry " + IntToString(w.nanobots) + ".";
    this.Log(msg);
    if s.notices {
      w.Notice(msg, SimpleMessageType.Neutral);
    };
    return msg;
  }

  private final static func Clock(minutes: Int32) -> String {
    let h: Int32 = minutes / 60;
    let m: Int32 = minutes % 60;
    if h <= 0 {
      return IntToString(m) + " min";
    };
    return IntToString(h) + "h" + (m < 10 ? "0" : "") + IntToString(m);
  }

  private final static func Eddies(v: Int32) -> String {
    let s: String = IntToString(v);
    let n: Int32 = StrLen(s);
    let out: String = "";
    let i: Int32 = 0;
    while i < n {
      if i > 0 && (n - i) % 3 == 0 {
        out += ",";
      };
      out += StrMid(s, i, 1);
      i += 1;
    };
    return out;
  }

  private final func Pay(amount: Int32, medical: Bool, detail: String) -> Bool {
    let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(this.GetGameInstance());
    if amount <= 0 {
      return true;
    };
    if !IsDefined(this.m_player) || ts.GetItemQuantity(this.m_player, MarketSystem.Money()) < amount {
      return false;
    };
    CCU_Tag(this.GetGameInstance(), medical, detail);
    return ts.RemoveItem(this.m_player, MarketSystem.Money(), amount);
  }

  // --- checkout

  public final func Checkout(gen: Int32) -> Void {
    let gi: GameInstance = this.GetGameInstance();
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let w: ref<ChromeWear> = this.Wear();
    let parts: String = "";
    let total: Int32 = 0;
    let minutes: Float = 0.0;
    let count: Int32;
    let cost: Int32;
    let a: Int32;
    let i: Int32;
    let plan: ref<ChromeRepairPlan>;
    let serviced: String = "";
    let skipped: String = "";
    let svcCost: Int32 = 0;
    let svcN: Int32 = 0;
    let c: Float;
    let surgeryMin: Float = 0.0;
    let procs: array<Float>;
    let procArea: array<Int32>;
    let regionMin: array<Float>;
    let recovered: String = "";
    let deck: Bool = this.m_deck;
    let chair: Bool = this.m_chair;
    let surgeryVisit: Bool = ArraySize(this.m_installs) > 0 || ArraySize(this.m_removals) > 0;
    let skipSec: Int32;
    let fx: ref<ChromeClinicGlitchOff>;
    let tier: Int32 = this.m_tier;
    let quality: Bool;
    let quote: ref<ChromeQuote>;
    let timeMult: Float = 1.0;
    let compChance: Float = 0.0;
    let recent: Bool;
    let comps: String = "";
    let compFatigue: Float = 0.0;
    let r: Int32;
    if gen != this.m_gen || !IsDefined(s) || !IsDefined(this.m_player) {
      this.m_open = false;
      return;
    };
    this.m_open = false;
    if IsDefined(w) {
      w.RefreshCounts();
    };
    // 1.2.0: clinic quality and complication odds, decided before anything moves the clock.
    quality = s.clinicQuality && !deck;
    if quality {
      if tier <= 0 {
        timeMult = 1.25;
      } else {
        if tier >= 2 {
          timeMult = 0.85;
        };
      };
    };
    recent = this.postOpUntil > 0.0 && this.GameNow() < this.postOpUntil;
    if s.complications {
      if deck {
        compChance = 0.10;
      } else {
        compChance = tier <= 0 ? 0.08 : (tier >= 2 ? 0.01 : 0.03);
      };
      if recent {
        compChance *= 2.0;
      };
    };

    // 1. Trauma care. 1.3.0: by button (paid in the screen, billed here) or automatic.
    if this.m_traumaPaid > 0 || StrLen(this.m_traumaPart) > 0 {
      total += this.m_traumaPaid;
      minutes += this.m_traumaMin;
      parts += this.m_traumaPart;
    };
    this.ClearTrauma();
    if s.traumaCare && !s.traumaButton && chair && !deck {
      count = CCU_InjuryCount(gi);
      if count > 0 {
        c = CCU_TTCoverage(this.m_player);
        i = CCU_TraumaCost(count);
        cost = Cast<Int32>(Cast<Float>(i) * (1.0 - c));
        if this.Pay(cost, true, "trauma care") {
          CCU_TraumaClear(gi);
          total += cost;
          minutes += Cast<Float>(CCU_TraumaMinutes(count));
          parts += " · trauma care " + ChromeClinic.Eddies(cost) + " (" + IntToString(count) + (count == 1 ? " injury" : " injuries") + (c > 0.0 ? ", Trauma Team paid " + IntToString(Cast<Int32>(c * 100.0)) + " %)" : ")");
          this.Log("trauma care " + IntToString(count) + " injuries, bill " + IntToString(i) + " eb, TT share " + FloatToStringPrec(c, 2) + ", V paid " + IntToString(cost) + " eb");
        } else {
          parts += " · trauma care refused, " + ChromeClinic.Eddies(cost) + " needed";
          this.Log("trauma care refused: " + IntToString(cost) + " eb needed");
        };
      };
    };

    // 2. Service, worst system first, as far as V can pay.
    if s.service && chair && !deck && IsDefined(w) {
      // 1.5.0: materials + fee (ChromeRepair), every clinic to 100 %, Viktor's friend rate.
      // 1.6.0: one plan, worst first, components from V's bag first (PlanRepairs).
      plan = this.PlanRepairs(-1, surgeryVisit ? 95.0 : 60.0, this.Money(), tier, Equals(this.m_vendorID, ChromeRepair.Viktor()));
      skipped = plan.skipped;
      if plan.skippedN > 0 {
        this.Log("service skipped (not affordable): " + plan.skipped);
      };
      a = 0;
      while a < ArraySize(plan.quotes) {
        quote = plan.quotes[a];
        i = quote.area;
        c = quote.cond;
        cost = quote.total;
        if this.Pay(cost, false, "chrome service " + ChromeArea.Name(i)) {
          if quote.ownN > 0 && !ChromeRepair.Take(gi, this.m_player, quote.own) {
            this.Log("service " + ChromeArea.Name(i) + ": components from the bag short (" + quote.ownText + "), repaired anyway");
          };
          w.Restore(i, 100.0);
          svcCost += cost;
          svcN += 1;
          minutes += Cast<Float>(quote.minutes);
          serviced += (StrLen(serviced) > 0 ? ", " : "") + ChromeArea.Name(i) + " " + IntToString(Cast<Int32>(c)) + "%";
          this.Log("service " + ChromeArea.Name(i) + " " + FloatToStringPrec(c, 1) + " % -> 100 | components " + quote.partsText + ", from the bag " + quote.ownText + ", bought " + quote.buyText + " = " + IntToString(quote.mat) + " + fee " + IntToString(quote.fee) + " (-" + IntToString(quote.cut) + " %) = " + IntToString(cost) + " eb");
        } else {
          skipped += (StrLen(skipped) > 0 ? ", " : "") + ChromeArea.Name(i) + " " + ChromeClinic.Eddies(cost);
          this.Log("service skipped " + ChromeArea.Name(i) + " " + FloatToStringPrec(c, 1) + " % | " + IntToString(cost) + " eb not affordable");
        };
        a += 1;
      };
      if svcN > 0 {
        total += svcCost;
        parts += " · service " + ChromeClinic.Eddies(svcCost) + " (" + serviced + (plan.ownN > 0 ? "; from your bag " + plan.ownText : "") + ")";
      };
      if StrLen(skipped) > 0 {
        parts += " · can't pay service for " + skipped;
      };
    };

    // 3. Surgery.
    if s.surgery && (ArraySize(this.m_installs) > 0 || ArraySize(this.m_removals) > 0) {
      i = 0;
      while i < ArraySize(this.m_installs) {
        ArrayPush(procs, ChromeClinic.SurgeryBase(this.m_installs[i]));
        ArrayPush(procArea, this.m_installs[i]);
        i += 1;
      };
      i = 0;
      while i < ArraySize(this.m_removals) {
        if !ArrayContains(this.m_installs, this.m_removals[i]) {
          ArrayPush(procs, 0.4 * ChromeClinic.SurgeryBase(this.m_removals[i]));
          ArrayPush(procArea, this.m_removals[i]);
        };
        i += 1;
      };
      // Longest operation at full time, the rest at 60 % (same session, same anaesthesia).
      i = 0;
      a = 0;
      while i < ArraySize(procs) {
        if procs[i] > procs[a] {
          a = i;
        };
        i += 1;
      };
      i = 0;
      while i < 6 {
        ArrayPush(regionMin, 0.0);
        i += 1;
      };
      i = 0;
      while i < ArraySize(procs) {
        c = procs[i] * (i == a ? 1.0 : 0.6) * Cast<Float>(s.surgeryTimePct) / 100.0 * (deck ? 1.5 : 1.0) * timeMult;
        surgeryMin += c;
        count = 0;
        while count < 6 {
          if ChromeClinic.InRegion(procArea[i], count) {
            regionMin[count] = regionMin[count] + c;
          };
          count += 1;
        };
        if compChance > 0.0 && RandF() < compChance {
          // Complication: out of calibration, and the region needs 4 h more recovery (chest: fatigue).
          // A removal that emptied the system has nothing left to calibrate (counts were refreshed above).
          if IsDefined(w) {
            w.Restore(procArea[i], w.HasChrome(procArea[i]) ? 80.0 : 100.0);
          };
          r = 0;
          while r < 6 {
            if ChromeClinic.InRegion(procArea[i], r) {
              regionMin[r] = regionMin[r] + 240.0;
              if r == 1 {
                compFatigue = 12.0;
              };
            };
            r += 1;
          };
          comps += (StrLen(comps) > 0 ? ", " : "") + ChromeArea.Name(procArea[i]);
          this.Log("complication " + ChromeArea.Name(procArea[i]) + " (chance " + FloatToStringPrec(compChance * 100.0, 0) + " %" + (recent ? ", still recovering from the last surgery" : "") + ")");
        } else {
          if IsDefined(w) {
            w.Restore(procArea[i], 100.0);
          };
        };
        i += 1;
      };
      if surgeryMin > 960.0 {
        surgeryMin = 960.0;
      };
      minutes += surgeryMin;
      parts += " · surgery " + ChromeClinic.Clock(Cast<Int32>(surgeryMin)) + " (" + IntToString(ArraySize(procs)) + (ArraySize(procs) == 1 ? " procedure)" : " procedures)");
      if StrLen(comps) > 0 {
        parts += " · COMPLICATION: " + comps + " out of calibration";
      };
      this.Log("surgery " + IntToString(ArraySize(procs)) + " procedures, " + FloatToStringPrec(surgeryMin, 0) + " min" + (deck ? " (RipperDeck x1.5)" : "") + (quality ? " | " + ChromeClinic.TierName(tier) + " x" + FloatToStringPrec(timeMult, 2) : "") + " | complication chance " + FloatToStringPrec(compChance * 100.0, 0) + " %");
    };

    // 4. The clock moves.
    if minutes >= 1.0 {
      skipSec = Cast<Int32>(minutes * 60.0);
      GameObjectEffectHelper.StartEffectEvent(this.m_player, n"time_skip_glitch", false);
      fx = new ChromeClinicGlitchOff();
      fx.player = this.m_player;
      GameInstance.GetDelaySystem(gi).DelayCallback(fx, 1.0, false);
      CCU_SkipTime(gi, skipSec);
    };
    // 1.6.1: chair-time drift settled now, serviced / implanted systems keep their restored value.
    if IsDefined(w) {
      w.SettleAfterSkip();
    };

    // 5. Recovery after surgery.
    if s.surgery && s.recovery && surgeryMin > 0.0 {
      recovered = this.ApplyRecovery(regionMin, surgeryMin + compFatigue * 20.0);
    };

    if IsDefined(w) {
      w.UpdateTiers(false);
    };
    if StrLen(parts) == 0 {
      return;
    };
    this.Log("checkout " + this.m_vendor + (quality ? " (" + ChromeClinic.TierName(tier) + ")" : "") + " | total " + IntToString(total) + " eb | " + FloatToStringPrec(minutes, 0) + " min");
    if s.notices && IsDefined(w) {
      w.Notice(this.m_vendor + (quality && tier != 1 ? " (" + ChromeClinic.TierName(tier) + ")" : "") + parts + " · total " + ChromeClinic.Eddies(total) + " eddies, " + ChromeClinic.Clock(Cast<Int32>(minutes)) + " in the chair" + recovered, SimpleMessageType.Neutral);
    };
  }

  // Body system -> Injuries regions (0 head, 1 torso, 2-3 arms, 4-5 legs).
  public final static func InRegion(a: Int32, region: Int32) -> Bool {
    if region == 0 {
      return a == ChromeArea.Frontal() || a == ChromeArea.OS() || a == ChromeArea.Eyes() || a == ChromeArea.Nervous();
    };
    if region == 1 {
      return a == ChromeArea.Cardio() || a == ChromeArea.Skin() || a == ChromeArea.Immune();
    };
    if region == 2 || region == 3 {
      return a == ChromeArea.Arms() || a == ChromeArea.Hands() || a == ChromeArea.Skeleton();
    };
    if region == 4 || region == 5 {
      return a == ChromeArea.Legs() || a == ChromeArea.Skeleton();
    };
    return false;
  }

  private final func ApplyRecovery(regionMin: array<Float>, surgeryMin: Float) -> String {
    let gi: GameInstance = this.GetGameInstance();
    let names: String = "";
    let r: Int32 = 0;
    let tier: Int32;
    let hours: Float;
    // Head, arms and legs heal like a light injury; the torso (no bleeding for a clean incision) only gets the fatigue.
    while r < 6 {
      if r != 1 && regionMin[r] > 0.0 {
        tier = regionMin[r] >= 240.0 ? 2 : 1;
        if CCU_PostOp(gi, r, tier) {
          if r == 0 { names += (StrLen(names) > 0 ? ", " : "") + "head"; };
          if r == 2 { names += (StrLen(names) > 0 ? ", " : "") + "arms"; };
          if r == 4 { names += (StrLen(names) > 0 ? ", " : "") + "legs"; };
        };
      };
      r += 1;
    };
    hours = MinF(36.0, 3.0 * surgeryMin / 60.0);
    this.postOpUntil = MaxF(this.postOpUntil, this.GameNow() + hours * 3600.0);
    if ArraySize(this.m_postOpMods) == 0 {
      this.ApplyFatigue();
    };
    this.Log("recovery: injuries " + (StrLen(names) > 0 ? names : "none") + " | fatigue " + FloatToStringPrec(hours, 1) + " game h");
    return " · recovery " + FloatToStringPrec(hours, 0) + " h" + (StrLen(names) > 0 ? " (" + names + "; sleep helps)" : "");
  }
}

// ---------------------------------------------------------------- ripperdoc hooks (all call through)

// A visit opens with the vendor hub (one per visit, unlike the cyberware tab).
@wrapMethod(VendorHubMenuGameController)
protected cb func OnSetUserData(userData: ref<IScriptable>) -> Bool {
  let r: Bool = wrappedMethod(userData);
  let c: ref<ChromeClinic>;
  if this.m_isRipperdoc && IsDefined(this.m_VendorDataManager) {
    c = ChromeClinic.Get(GetGameInstance());
    if IsDefined(c) {
      c.BeginFromHub(ChromeClinic.VendorName(this.m_VendorDataManager.GetVendorID()), CCU_RipperTier(this.m_VendorDataManager.GetVendorID()));
      c.NoteHub(this.m_VendorDataManager.GetVendorInstance(), this.m_VendorDataManager.GetVendorID());
    };
  };
  return r;
}

@wrapMethod(VendorHubMenuGameController)
protected cb func OnUninitialize() -> Bool {
  let c: ref<ChromeClinic>;
  if this.m_isRipperdoc {
    c = ChromeClinic.Get(GetGameInstance());
    if IsDefined(c) {
      c.End();
    };
  };
  return wrappedMethod();
}

// The cyberware screen = V sat in the chair.
@wrapMethod(RipperDocGameController)
protected cb func OnInitialize() -> Bool {
  let r: Bool = wrappedMethod();
  let c: ref<ChromeClinic> = ChromeClinic.Get(GetGameInstance());
  if IsDefined(c) && Equals(this.m_screen, CyberwareScreenType.Ripperdoc) && IsDefined(this.m_VendorDataManager) && !IsDefined(this.m_VendorDataManager.GetVendorInstance() as PlayerPuppet) {
    c.SatInChair();
  };
  return r;
}

// RipperDeck (or a ripper without the hub): the visit ends with the cyberware screen.
@wrapMethod(RipperDocGameController)
protected cb func OnUninitialize() -> Bool {
  let c: ref<ChromeClinic> = ChromeClinic.Get(GetGameInstance());
  if IsDefined(c) && c.EndsWithScreen() {
    c.End();
  };
  return wrappedMethod();
}

@wrapMethod(RipperDocGameController)
private final func EquipCyberware(itemData: wref<gameItemData>) -> Bool {
  let c: ref<ChromeClinic> = ChromeClinic.Get(GetGameInstance());
  let area: gamedataEquipmentArea = this.m_hoverArea;
  let deck: Bool = IsDefined(this.m_VendorDataManager) && IsDefined(this.m_VendorDataManager.GetVendorInstance() as PlayerPuppet);
  let ok: Bool;
  if IsDefined(itemData) && Equals(area, gamedataEquipmentArea.Invalid) {
    area = EquipmentSystem.GetEquipAreaType(itemData.GetID());
  };
  if IsDefined(c) {
    c.SetInEquip(true);
  };
  ok = wrappedMethod(itemData);
  if IsDefined(c) {
    c.SetInEquip(false);
    if ok {
      c.NoteInstall(area, deck);
    };
  };
  return ok;
}

@wrapMethod(RipperDocGameController)
// 2.5 port: game 2.5 added `opt itemToEquip` (ripperdoc.swift UnequipCyberware)
private final func UnequipCyberware(itemData: wref<gameItemData>, opt itemToEquip: wref<gameItemData>, opt skipRefresh: Bool) -> Bool {
  let c: ref<ChromeClinic> = ChromeClinic.Get(GetGameInstance());
  let area: gamedataEquipmentArea = this.m_hoverArea;
  let deck: Bool = IsDefined(this.m_VendorDataManager) && IsDefined(this.m_VendorDataManager.GetVendorInstance() as PlayerPuppet);
  let ok: Bool = wrappedMethod(itemData, itemToEquip, skipRefresh);
  if IsDefined(itemData) && Equals(area, gamedataEquipmentArea.Invalid) {
    area = EquipmentSystem.GetEquipAreaType(itemData.GetID());
  };
  if ok && IsDefined(c) {
    c.NoteRemoval(area, deck);
  };
  return ok;
}

// ---------------------------------------------------------------- 1.3.0: Treat injuries button

// A ripper's chair, not a RipperDeck self-install.
@addMethod(RipperDocGameController)
private final func CCU_IsRipperChair() -> Bool {
  return Equals(this.m_screen, CyberwareScreenType.Ripperdoc) && IsDefined(this.m_VendorDataManager) && !IsDefined(this.m_VendorDataManager.GetVendorInstance() as PlayerPuppet);
}

@addMethod(RipperDocGameController)
private final func CCU_AddTreatHint() -> Void {
  let c: ref<ChromeClinic> = ChromeClinic.Get(GetGameInstance());
  let n: Int32;
  if !IsDefined(c) || !c.TraumaButtonOn() || !this.CCU_IsRipperChair() {
    return;
  };
  n = c.TraumaCount();
  if n > 0 {
    this.m_buttonHintsController.AddButtonHint(n"cyberslop_treat_injuries", "Treat injuries (" + IntToString(n) + ") (" + IntToString(c.TraumaCost(n)) + ")€$");
  } else {
    this.m_buttonHintsController.RemoveButtonHint(n"cyberslop_treat_injuries");
  };
}

@wrapMethod(RipperDocGameController)
private final func SetButtonHints(toDefault: Bool, opt isClose: Bool) -> Void {
  wrappedMethod(toDefault, isClose);
  this.CCU_AddTreatHint();
}

@wrapMethod(RipperDocGameController)
protected cb func OnReleaseInput(e: ref<inkPointerEvent>) -> Bool {
  let c: ref<ChromeClinic>;
  let r: Int32;
  let note: ref<UIMenuNotificationEvent>;
  if e.IsAction(n"cyberslop_treat_injuries") && this.CCU_IsRipperChair() {
    c = ChromeClinic.Get(GetGameInstance());
    if IsDefined(c) && c.TraumaButtonOn() {
      r = c.TreatNow(IsDefined(this.m_VendorDataManager) ? this.m_VendorDataManager.GetVendorName() : "");
      if r == 0 {
        this.m_audioSystem.Play(n"ui_menu_onpress");
        this.m_audioSystem.Play(n"OnSell");
        this.m_buttonHintsController.RemoveButtonHint(n"cyberslop_treat_injuries");
      } else {
        if r == 2 {
          note = new UIMenuNotificationEvent();
          note.m_notificationType = UIMenuNotificationType.VNotEnoughMoney;
          this.m_uiSystem.QueueEvent(note);
        } else {
          this.m_buttonHintsController.RemoveButtonHint(n"cyberslop_treat_injuries");
        };
      };
    };
  };
  return wrappedMethod(e);
}

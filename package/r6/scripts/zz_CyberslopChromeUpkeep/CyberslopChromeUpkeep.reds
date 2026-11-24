// Cyberslop Chrome Upkeep 1.7.2 (2026-11-23), for game 2.5 and Dark Future 3.0.
// 1.7.2: the regen / buff-duration floors follow other mods' modifiers that come and go (Dark Future hydration etc.):
//   every tick compares those stats without this mod's part to the value used at the last build and rebuilds when it
//   moved (was: only on a 5 % band change, so stamina regen could go below -100 %). Arm stamina penalty reaches its
//   full +160 % (ChromeUpkeepStatLimits.yaml lowers the three arm stamina stats' floor from -1 to -2).
// 1.7.1: worn nervous-system chrome no longer switches off Synaptic Accelerator / Reflex Recorder / Grenade Spotter
//   slow time (their "duration bonus Equal 0" check now also takes negative values, ChromeUpkeepDurationPrereqs).
// 1.7.0: harsher, graded penalties (design goal: "harsher, more realistic and immersive"): every system with chrome now has one,
//   they start below 80 % and grow in 5 % steps to the full value at 0 % (Severity), setting "Penalty strength (%)".
//   New: optics (crit chance, aim speed), circulatory (stamina, stamina regen), immune (health regen), skeleton
//   (carry weight), hands (reload, recoil). Malfunctions from 60 % down (chance 60 - condition), dead below 10 %.
//   Review fixes: restores held through the first tick after the chair; wear / drift log strings only
//   built with the log on.
// 1.6.1: a ripper repair ended at 99.5 %, not 100 %: the clinic restored the systems, then moved the clock, and the
//   next tick charged the 1 %/day drift for the whole chair time to the fresh chrome. Now the clinic settles the
//   drift after its clock skip and re-applies the restores (SettleAfterSkip). Live log: with "Log to CET gamelog" on,
//   every line also goes straight to <game>\r6\storages\CyberslopChromeUpkeep\chrome-<n>.txt (RedFileSystem,
//   one file per launch, survives a crash; CET's gamelog is buffered), plus restore / drift / wear lines.
// 1.6.0: ripper repairs use the components in V's bag first and charge only for the missing ones (setting
//   "Repairs use your components", on).
// 1.5.0: repair priced from the parts (CyberslopChromeRepair.reds): materials at market price + the ripper's fee
//   (clinic tier, Street Cred, Viktor), every ripper repairs to 100 %, repair at the ripper from the Cyberslop
//   Chrome Clinic CET window, nanobot canisters (field repair to 50 %, 60 game min, components from the bag).
//   DIY field maintenance removed (nanobots replace it).
// 1.4.0 (2026-11-17): code port only, see CyberslopChromeClinic.reds
// 1.3.0 (2026-11-07;1.1.0: DIY field maintenance, clinic session end fix; 1.2.0: clinic quality, complications; 1.2.1: review fixes; 1.3.0: Treat injuries button)
// Chrome is machinery: actuators, seals, coolant, bio-interfaces. Use wears it, rippers service it,
// and putting it in is surgery.
//   WEAR      Each body system with chrome in it has a condition (100 % new). Use wears it:
//             Sandevistan / Berserk / Overclock fires and quickhack uploads (operating system),
//             Kerenzikov (nervous system), cyberarm swings and launcher shots (arms), double /
//             charged jumps and air dashes (legs), Optical Camo (skin), Blood Pump (circulatory),
//             hits taken (subdermal plating and bone lacing), plus 1 % per game day for every
//             system (bio-interface drift).
//   PENALTY   Below 60 % "worn", below 30 % "failing": longer cyberware cooldowns, shorter
//             Kerenzikov / buffs, more stamina per cyberarm swing, lower jumps, less armor,
//             more RAM per quickhack / slower RAM regen. Failing operating system or nervous system
//             can glitch out on activation (vanilla "cyberware disabled" debuff, 12 s).
//   CLINIC    (CyberslopChromeClinic.reds) Sitting in a ripperdoc's chair: they treat injuries
//             (Injuries mod), repair worn chrome (materials + fee, CyberslopChromeRepair.reds), and
//             every implant installed or removed takes surgery time, followed by recovery.
//   FIELD     Nanobot canisters (CyberslopChromeRepair.reds): up to 50 % anywhere, at a steep price.
// Mod Settings > Cyberslop Chrome Upkeep. Conditions are kept in the save.
module CyberslopChromeUpkeep

@if(ModuleExists("DigitalVixenCore"))
import DigitalVixenCore.*

@if(ModuleExists("RedFileSystem"))
import RedFileSystem.*

// ---------------------------------------------------------------- live log (1.6.1)
// RedFileSystem grants a storage only once per process, so a service holds it. Each line is appended at once.

@if(ModuleExists("RedFileSystem"))
public class ChromeLiveLog extends ScriptableService {
  private let file: ref<File>;

  private cb func OnLoad() -> Void {
    let storage: ref<FileSystemStorage> = FileSystem.GetStorage("CyberslopChromeUpkeep");
    if !IsDefined(storage) {
      return;
    };
    let number: Int32 = ArraySize(storage.GetFiles()) + 1;
    while Equals(storage.Exists(s"chrome-\(number).txt"), FileSystemStatus.True) {
      number += 1;
    };
    this.file = storage.GetFile(s"chrome-\(number).txt");
  }

  public final func Write(line: String) -> Void {
    if IsDefined(this.file) {
      this.file.WriteText(line + "\n", FileSystemWriteMode.Append);
    };
  }
}

@if(ModuleExists("RedFileSystem"))
func ChromeLiveLogWrite(line: String) -> Void {
  let svc: ref<ChromeLiveLog> = GameInstance.GetScriptableServiceContainer().GetService(n"CyberslopChromeUpkeep.ChromeLiveLog") as ChromeLiveLog;
  if IsDefined(svc) {
    svc.Write(line);
  };
}

@if(!ModuleExists("RedFileSystem"))
func ChromeLiveLogWrite(line: String) -> Void {}

// ---------------------------------------------------------------- body systems

public abstract class ChromeArea {
  public static func Count() -> Int32 = 11
  public static func Frontal() -> Int32 = 0
  public static func OS() -> Int32 = 1
  public static func Eyes() -> Int32 = 2
  public static func Cardio() -> Int32 = 3
  public static func Nervous() -> Int32 = 4
  public static func Skin() -> Int32 = 5
  public static func Immune() -> Int32 = 6
  public static func Skeleton() -> Int32 = 7
  public static func Arms() -> Int32 = 8
  public static func Hands() -> Int32 = 9
  public static func Legs() -> Int32 = 10

  public static func ToEquipmentArea(a: Int32) -> gamedataEquipmentArea {
    switch a {
      case 0: return gamedataEquipmentArea.FrontalCortexCW;
      case 1: return gamedataEquipmentArea.SystemReplacementCW;
      case 2: return gamedataEquipmentArea.EyesCW;
      case 3: return gamedataEquipmentArea.CardiovascularSystemCW;
      case 4: return gamedataEquipmentArea.NervousSystemCW;
      case 5: return gamedataEquipmentArea.IntegumentarySystemCW;
      case 6: return gamedataEquipmentArea.ImmuneSystemCW;
      case 7: return gamedataEquipmentArea.MusculoskeletalSystemCW;
      case 8: return gamedataEquipmentArea.ArmsCW;
      case 9: return gamedataEquipmentArea.HandsCW;
      case 10: return gamedataEquipmentArea.LegsCW;
    };
    return gamedataEquipmentArea.Invalid;
  }

  public static func FromEquipmentArea(e: gamedataEquipmentArea) -> Int32 {
    let a: Int32 = 0;
    while a < ChromeArea.Count() {
      if Equals(ChromeArea.ToEquipmentArea(a), e) {
        return a;
      };
      a += 1;
    };
    return -1;
  }

  public static func Name(a: Int32) -> String {
    switch a {
      case 0: return "frontal cortex";
      case 1: return "operating system";
      case 2: return "optics";
      case 3: return "circulatory system";
      case 4: return "nervous system";
      case 5: return "subdermal / skin";
      case 6: return "immune system";
      case 7: return "skeleton";
      case 8: return "arms";
      case 9: return "hands";
      case 10: return "legs";
    };
    return "?";
  }

  // Wear in plain words, for notices.
  public static func Symptom(a: Int32) -> String {
    switch a {
      case 0: return "cortex chips running hot";
      case 1: return "OS firmware drifting";
      case 2: return "optics losing calibration";
      case 3: return "pumps and filters clogging";
      case 4: return "reflex boosters misfiring";
      case 5: return "plating seams loosening";
      case 6: return "filters saturated";
      case 7: return "lacing micro-fractures";
      case 8: return "arm actuators grinding";
      case 9: return "hand servos sticking";
      case 10: return "leg actuators and tendons slipping";
    };
    return "wear";
  }
}

// ---------------------------------------------------------------- settings

public class ChromeUpkeepSettings extends ScriptableSystem {

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Wear")
  @runtimeProperty("ModSettings.displayName", "Chrome wear")
  @runtimeProperty("ModSettings.description", "Use wears installed chrome (per body system). Off = conditions freeze where they are.")
  public let wear: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Wear")
  @runtimeProperty("ModSettings.displayName", "Wear rate (%)")
  @runtimeProperty("ModSettings.description", "Scales all wear. 100 = a heavy Sandevistan or Kerenzikov user reaches 'worn' after about 2-3 real hours of fights.")
  @runtimeProperty("ModSettings.step", "10")
  @runtimeProperty("ModSettings.min", "10")
  @runtimeProperty("ModSettings.max", "300")
  @runtimeProperty("ModSettings.dependency", "wear")
  public let wearRate: Int32 = 100;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Wear")
  @runtimeProperty("ModSettings.displayName", "Worn and failing penalties")
  @runtimeProperty("ModSettings.description", "1.7.0: every system with chrome loses performance below 80 %, growing in 5 % steps to the full penalty at 0 %: longer cooldowns and more RAM per hack (OS), slower RAM regen (cortex), lower crit chance and slower aim (optics), less stamina and stamina regen (circulatory), shorter cyberware buffs (nervous), slower healing (immune), less armor (plating), less carry weight (skeleton), more stamina per arm swing (arms), slower reloads and more recoil (hands), lower jumps (legs).")
  @runtimeProperty("ModSettings.dependency", "wear")
  public let penalties: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Wear")
  @runtimeProperty("ModSettings.displayName", "Penalty strength (%)")
  @runtimeProperty("ModSettings.description", "Scales every worn-chrome penalty. 100 = the 1.7.0 set (at 30 %: cooldowns +56 %, reloads +50 %, recoil +62 %, armor -37 %, jumps -37 %, stamina regen -50 % ...).")
  @runtimeProperty("ModSettings.step", "10")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "200")
  @runtimeProperty("ModSettings.dependency", "penalties")
  public let penaltyStrength: Int32 = 100;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Wear")
  @runtimeProperty("ModSettings.displayName", "Malfunctions")
  @runtimeProperty("ModSettings.description", "Operating system (Sandevistan, Berserk, Overclock) and nervous system (Kerenzikov) can glitch out on activation (cyberware disabled 12 s): chance = 60 minus the condition (at 30 %: 30 % chance), and below 10 % the chrome is dead and always fails.")
  @runtimeProperty("ModSettings.dependency", "wear")
  public let malfunctions: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Clinic")
  @runtimeProperty("ModSettings.displayName", "Ripperdoc service")
  @runtimeProperty("ModSettings.description", "Sitting in a ripperdoc's chair: systems below 60 % (below 95 % when an implant goes in or out) are repaired to 100 % automatically, worst first, as far as V can pay. Any system can be repaired at a ripper from the Cyberslop Chrome Clinic window.")
  public let service: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Clinic")
  @runtimeProperty("ModSettings.displayName", "Repair price (%)")
  @runtimeProperty("ModSettings.description", "Scales ripper repairs (materials and fee). 100: materials = 3 % of the implants' base price per 100 % wear, in components of the implant's quality at market price; fee = 4 % per 100 % wear (min 250), x0.75 street / x1.3 top clinic, minus up to 60 % for Street Cred, Viktor another 15 % off.")
  @runtimeProperty("ModSettings.step", "5")
  @runtimeProperty("ModSettings.min", "25")
  @runtimeProperty("ModSettings.max", "300")
  public let repairPricePct: Int32 = 100;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Clinic")
  @runtimeProperty("ModSettings.displayName", "Repairs use your components")
  @runtimeProperty("ModSettings.description", "On: the ripper (clinic window and chair service) first uses the components in your bag, of each implant's own quality, and charges market price only for the ones you are missing. Off: every component is bought from the ripper.")
  public let repairUsesBag: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Clinic")
  @runtimeProperty("ModSettings.displayName", "Surgery takes time")
  @runtimeProperty("ModSettings.description", "Implants installed or removed at a ripperdoc take surgery time when you leave the chair (1-4 h each, less for the next ones in the same visit), Dark Future needs included.")
  public let surgery: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Clinic")
  @runtimeProperty("ModSettings.displayName", "Surgery time (%)")
  @runtimeProperty("ModSettings.step", "10")
  @runtimeProperty("ModSettings.min", "10")
  @runtimeProperty("ModSettings.max", "200")
  @runtimeProperty("ModSettings.dependency", "surgery")
  public let surgeryTimePct: Int32 = 100;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Clinic")
  @runtimeProperty("ModSettings.displayName", "Post-op recovery")
  @runtimeProperty("ModSettings.description", "After surgery the operated region heals like a light injury (Injuries mod: limp, stiff arm, neural fog; sleep clears it) and V's stamina recovers slower for a while.")
  @runtimeProperty("ModSettings.dependency", "surgery")
  public let recovery: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Clinic")
  @runtimeProperty("ModSettings.displayName", "Clinic quality")
  @runtimeProperty("ModSettings.description", "Street / pro / top ripperdocs (Cyberslop Ripper Stock tiers): surgery time x1.25 / 1.0 / 0.85, complications 8 / 3 / 1 %. The repair fee (x0.75 / 1.0 / 1.3) applies with this off too.")
  @runtimeProperty("ModSettings.dependency", "surgery")
  public let clinicQuality: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Clinic")
  @runtimeProperty("ModSettings.displayName", "Surgical complications")
  @runtimeProperty("ModSettings.description", "Chance per procedure: street 8 %, pro 3 %, top 1 %, RipperDeck self-install 10 %; doubled while V is still recovering from the last surgery. A complication: the implant comes out of calibration at 80 % and the region needs 4 h more recovery.")
  @runtimeProperty("ModSettings.dependency", "surgery")
  public let complications: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Clinic")
  @runtimeProperty("ModSettings.displayName", "Nanobot canisters")
  @runtimeProperty("ModSettings.description", "Emergency field repair from the Cyberslop Chrome Clinic window: a canister (70,000 eddies at any ripperdoc, carry 10) brings every system below 50 % up to 50 % over 60 game minutes (waiting or sleeping counts), feeding on components from your bag: twice what a ripper uses, the implant's quality or higher.")
  public let nanobots: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Clinic")
  @runtimeProperty("ModSettings.displayName", "Ripperdoc trauma care")
  @runtimeProperty("ModSettings.description", "Sitting in a ripperdoc's chair with injuries (Injuries mod): the ripper treats them at the Injuries doctor price and time.")
  public let traumaCare: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Clinic")
  @runtimeProperty("ModSettings.displayName", "Trauma care by button")
  @runtimeProperty("ModSettings.description", "On: the cyberware screen shows a Treat injuries button with the price, nothing is treated unless you press it. Off: every injury is treated automatically when you leave the chair.")
  public let traumaButton: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Display")
  @runtimeProperty("ModSettings.displayName", "Notices")
  @runtimeProperty("ModSettings.description", "HUD line when a system turns worn or failing, and the clinic bill after a ripperdoc visit.")
  public let notices: Bool = true;

  @runtimeProperty("ModSettings.mod", "Cyberslop Chrome Upkeep")
  @runtimeProperty("ModSettings.category", "Display")
  @runtimeProperty("ModSettings.displayName", "Log to CET gamelog")
  @runtimeProperty("ModSettings.description", "[ChromeUpkeep] lines: tier changes, malfunctions, clinic bills (events only).")
  public let debugLog: Bool = true;

  private func OnAttach() -> Void {
    ModSettings.RegisterListenerToClass(this);
  }

  private func OnDetach() -> Void {
    ModSettings.UnregisterListenerToClass(this);
  }

  public static func Get(gi: GameInstance) -> ref<ChromeUpkeepSettings> {
    return GameInstance.GetScriptableSystemsContainer(gi).Get(n"CyberslopChromeUpkeep.ChromeUpkeepSettings") as ChromeUpkeepSettings;
  }
}

// ---------------------------------------------------------------- wear

public class ChromeWearTick extends DelayCallback {
  public let sys: wref<ChromeWear>;
  public let gen: Int32;

  public func Call() -> Void {
    if IsDefined(this.sys) {
      this.sys.Tick(this.gen);
    };
  }
}

public class ChromeWear extends ScriptableSystem {

  // Condition per body system in % (kept in the save). 100 = new.
  public persistent let cond: array<Float>;
  public persistent let lastPassive: Float;
  // 1.5.0: nanobot canisters carried, and the running dose (game time; % still to add and % per game second per system).
  public persistent let nanobots: Int32;
  public persistent let nanoUntil: Float;
  public persistent let nanoLast: Float;
  public persistent let nanoLeft: array<Float>;
  public persistent let nanoRate: array<Float>;

  private let m_player: wref<PlayerPuppet>;
  private let m_count: array<Int32>;
  private let m_tier: array<Int32>;
  private let m_mods: array<ref<gameStatModifierData>>;
  // 1.7.2: AddScaleMod bookkeeping (stat, other modifiers' total at build, own value) for CheckScaleDrift
  private let m_scaleStat: array<gamedataStatType>;
  private let m_scaleOthers: array<Float>;
  private let m_scaleOwn: array<Float>;
  private let m_gen: Int32;
  private let m_penaltiesOn: Bool;
  // 1.7.0: 5 % condition band per system the penalties were built for, and the strength setting they used.
  private let m_band: array<Int32>;
  private let m_strength: Int32;

  public static func Get(gi: GameInstance) -> ref<ChromeWear> {
    return GameInstance.GetScriptableSystemsContainer(gi).Get(n"CyberslopChromeUpkeep.ChromeWear") as ChromeWear;
  }

  private final func Settings() -> ref<ChromeUpkeepSettings> {
    return ChromeUpkeepSettings.Get(this.GetGameInstance());
  }

  public final func Log(msg: String) -> Void {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let gt: GameTime;
    if IsDefined(s) && s.debugLog {
      FTLog("[ChromeUpkeep] " + msg);
      gt = GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTime();
      ChromeLiveLogWrite("[day " + IntToString(GameTime.Days(gt)) + " " + IntToString(GameTime.Hours(gt)) + ":" + (GameTime.Minutes(gt) < 10 ? "0" : "") + IntToString(GameTime.Minutes(gt)) + " | sim " + FloatToStringPrec(EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGameInstance())), 0) + " s] " + msg);
    };
  }

  // 1.6.1: restores of the current clinic checkout, re-applied after its clock skip (SettleAfterSkip).
  private let m_pendingArea: array<Int32>;
  private let m_pendingCond: array<Float>;

  // 1.6.1: the clinic calls this after it moved the clock: the drift for the chair time goes to every system,
  // then the systems it restored this checkout are set again, so they leave the chair at the restored value.
  public final func SettleAfterSkip() -> Void {
    let i: Int32 = 0;
    this.Ensure();
    this.Passive(true);
    while i < ArraySize(this.m_pendingArea) {
      this.cond[this.m_pendingArea[i]] = this.m_pendingCond[i];
      i += 1;
    };
    if ArraySize(this.m_pendingArea) > 0 {
      this.Log("settled after the chair: " + IntToString(ArraySize(this.m_pendingArea)) + " restored systems kept at their restored value");
    };
    // build 2 (review 2c): the list stays until the next tick, which re-applies it after its own drift, in case
    // the clock skip only shows in GetGameTimeStamp a frame later.
  }

  private func OnAttach() -> Void {
    this.RegisterDV();
  }

  // Hits by body region (DigitalVixen Core's hit location): the chrome in that region takes them.
  @if(ModuleExists("DigitalVixenCore"))
  private final func RegisterDV() -> Void {
    GameInstance.GetCallbackSystem().RegisterCallback(n"DVCore/PlayerHit", this, n"OnDVHit").SetLifetime(CallbackLifetime.Forever);
  }

  @if(!ModuleExists("DigitalVixenCore"))
  private final func RegisterDV() -> Void {}

  @if(ModuleExists("DigitalVixenCore"))
  protected cb func OnDVHit(evt: ref<DVPlayerHitEvent>) -> Void {
    let maxHP: Float;
    let pct: Float;
    if !IsDefined(evt) || !IsDefined(this.m_player) || evt.damage <= 0.0 {
      return;
    };
    maxHP = GameInstance.GetStatsSystem(this.GetGameInstance()).GetStatValue(Cast<StatsObjectID>(this.m_player.GetEntityID()), gamedataStatType.Health);
    if maxHP <= 0.0 {
      return;
    };
    pct = 100.0 * evt.damage / maxHP;
    if evt.region == 0 {
      this.Wear(ChromeArea.Eyes(), 0.03 * pct, "head hit");
      this.Wear(ChromeArea.Frontal(), 0.01 * pct, "head hit");
    } else {
      if evt.region == 1 {
        this.Wear(ChromeArea.Cardio(), 0.01 * pct, "torso hit");
      } else {
        if evt.region == 2 || evt.region == 3 {
          this.Wear(ChromeArea.Arms(), 0.04 * pct, "arm hit");
          this.Wear(ChromeArea.Hands(), 0.02 * pct, "arm hit");
        } else {
          this.Wear(ChromeArea.Legs(), 0.04 * pct, "leg hit");
        };
      };
    };
  }

  private final func Ensure() -> Void {
    while ArraySize(this.cond) < ChromeArea.Count() {
      ArrayPush(this.cond, 100.0);
    };
    while ArraySize(this.m_count) < ChromeArea.Count() {
      ArrayPush(this.m_count, 0);
    };
    while ArraySize(this.m_tier) < ChromeArea.Count() {
      ArrayPush(this.m_tier, 0);
    };
    while ArraySize(this.nanoLeft) < ChromeArea.Count() {
      ArrayPush(this.nanoLeft, 0.0);
    };
    while ArraySize(this.nanoRate) < ChromeArea.Count() {
      ArrayPush(this.nanoRate, 0.0);
    };
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let i: Int32 = 0;
    this.m_player = GameInstance.GetPlayerSystem(request.owner.GetGame()).GetLocalPlayerMainGameObject() as PlayerPuppet;
    this.Ensure();
    // Stat modifiers are not saved: a load starts clean, the first tick puts them back.
    ArrayClear(this.m_mods);
    ArrayClear(this.m_scaleStat);
    ArrayClear(this.m_scaleOthers);
    ArrayClear(this.m_scaleOwn);
    this.m_penaltiesOn = false;
    while i < ChromeArea.Count() {
      this.m_tier[i] = -1;
      i += 1;
    };
    if this.lastPassive <= 0.0 {
      this.lastPassive = this.GameNow();
    };
    this.m_gen += 1;
    this.Schedule(3.0);
  }

  private final func GameNow() -> Float {
    return GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTimeStamp();
  }

  private final func Schedule(delay: Float) -> Void {
    let cb: ref<ChromeWearTick> = new ChromeWearTick();
    cb.sys = this;
    cb.gen = this.m_gen;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, delay, false);
  }

  public final func Tick(gen: Int32) -> Void {
    let i: Int32 = 0;
    if gen != this.m_gen {
      return;
    };
    this.RefreshCounts();
    this.Passive(false);
    // 1.6.1: restores of the last checkout hold through the first tick after it (clock skip seen late).
    while i < ArraySize(this.m_pendingArea) {
      this.cond[this.m_pendingArea[i]] = this.m_pendingCond[i];
      i += 1;
    };
    if ArraySize(this.m_pendingArea) > 0 {
      this.Log("first tick after the chair: " + IntToString(ArraySize(this.m_pendingArea)) + " restored systems re-applied");
    };
    ArrayClear(this.m_pendingArea);
    ArrayClear(this.m_pendingCond);
    this.NanoUpdate();
    this.UpdateTiers(false);
    this.ReapplyIfSettingsChanged();
    this.CheckScaleDrift();
    // A running nanobot dose shows its progress in steps of about 1 %.
    this.Schedule(this.nanoUntil > 0.0 ? 10.0 : 30.0);
  }

  public final func GetPlayerRef() -> wref<PlayerPuppet> = this.m_player

  public final func Now() -> Float = this.GameNow()

  public final func RefreshCounts() -> Void {
    let data: ref<EquipmentSystemPlayerData>;
    let a: Int32 = 0;
    this.Ensure();
    if !IsDefined(this.m_player) {
      return;
    };
    data = EquipmentSystem.GetData(this.m_player);
    if !IsDefined(data) {
      return;
    };
    while a < ChromeArea.Count() {
      this.m_count[a] = data.GetNumberOfItemsInEquipmentArea(ChromeArea.ToEquipmentArea(a));
      a += 1;
    };
  }

  public final func HasChrome(a: Int32) -> Bool {
    this.Ensure();
    return a >= 0 && a < ChromeArea.Count() && this.m_count[a] > 0;
  }

  public final func PieceCount(a: Int32) -> Int32 {
    this.Ensure();
    if a < 0 || a >= ChromeArea.Count() {
      return 0;
    };
    return this.m_count[a];
  }

  public final func Condition(a: Int32) -> Float {
    this.Ensure();
    if a < 0 || a >= ChromeArea.Count() {
      return 100.0;
    };
    return this.cond[a];
  }

  // 0 good, 1 worn (< 60 %), 2 failing (< 30 %).
  public final static func TierOf(c: Float) -> Int32 {
    if c < 30.0 {
      return 2;
    };
    if c < 60.0 {
      return 1;
    };
    return 0;
  }

  // 1.7.0: how hard a system's wear bites, 0 (80 % and up, or no chrome) to 1 (0 %), in 5 % steps.
  // Linear from 80 %: at 60 % 0.25, at 30 % 0.625, at 10 % 0.875.
  public final func Severity(a: Int32) -> Float {
    let band: Float;
    if !this.HasChrome(a) {
      return 0.0;
    };
    band = 5.0 * Cast<Float>(FloorF(this.Condition(a) / 5.0));
    if band >= 80.0 {
      return 0.0;
    };
    return ClampF((80.0 - band) / 80.0, 0.0, 1.0);
  }

  private final func BandOf(a: Int32) -> Int32 {
    if !this.HasChrome(a) {
      return 99;
    };
    return FloorF(this.Condition(a) / 5.0);
  }

  public final func Tier(a: Int32) -> Int32 {
    if !this.HasChrome(a) {
      return 0;
    };
    return ChromeWear.TierOf(this.Condition(a));
  }

  // 1 % per game day for every system with chrome in it.
  private final func Passive(force: Bool) -> Void {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let now: Float = this.GameNow();
    let days: Float = (now - this.lastPassive) / 86400.0;
    let a: Int32 = 0;
    let n: Int32 = 0;
    if days <= 0.0 || days > 30.0 {
      this.lastPassive = now;
      return;
    };
    if days < 0.02 && !force {
      return;
    };
    this.lastPassive = now;
    if !IsDefined(s) || !s.wear {
      return;
    };
    while a < ChromeArea.Count() {
      if this.HasChrome(a) {
        this.cond[a] = MaxF(0.0, this.cond[a] - days * 1.0 * Cast<Float>(s.wearRate) / 100.0);
        n += 1;
      };
      a += 1;
    };
    if s.debugLog {
      this.Log("drift " + FloatToStringPrec(days * 24.0, 2) + " game h" + (force ? " (after the chair)" : "") + ": -" + FloatToStringPrec(days * Cast<Float>(s.wearRate) / 100.0, 3) + " % on " + IntToString(n) + " systems");
    };
  }

  public final func Wear(a: Int32, amount: Float, why: String) -> Void {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    this.Ensure();
    if !IsDefined(s) || !s.wear || a < 0 || a >= ChromeArea.Count() || !this.HasChrome(a) || amount <= 0.0 {
      return;
    };
    this.cond[a] = MaxF(0.0, this.cond[a] - amount * Cast<Float>(s.wearRate) / 100.0);
    if s.debugLog {
      this.Log("wear " + ChromeArea.Name(a) + " -" + FloatToStringPrec(amount * Cast<Float>(s.wearRate) / 100.0, 3) + " % (" + why + ") -> " + FloatToStringPrec(this.cond[a], 2) + " %");
    };
    if ChromeWear.TierOf(this.cond[a]) != this.m_tier[a] {
      this.UpdateTiers(true);
    };
  }

  // Set by the clinic after a service; new chrome needs no service.
  public final func Restore(a: Int32, c: Float) -> Void {
    let old: Float;
    this.Ensure();
    if a >= 0 && a < ChromeArea.Count() {
      old = this.cond[a];
      this.cond[a] = ClampF(c, 0.0, 100.0);
      ArrayPush(this.m_pendingArea, a);
      ArrayPush(this.m_pendingCond, this.cond[a]);
      this.Log("restore " + ChromeArea.Name(a) + " " + FloatToStringPrec(old, 2) + " -> " + FloatToStringPrec(this.cond[a], 2) + " %");
    };
  }

  // Tier changes: notice, log, and rebuild the penalty modifiers (1.7.0: also on every 5 % band change).
  public final func UpdateTiers(announce: Bool) -> Void {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let changed: Bool = false;
    let a: Int32 = 0;
    let t: Int32;
    let b: Int32;
    let worse: String = "";
    this.Ensure();
    while ArraySize(this.m_band) < ChromeArea.Count() {
      ArrayPush(this.m_band, -1);
    };
    while a < ChromeArea.Count() {
      b = this.BandOf(a);
      if b != this.m_band[a] {
        this.m_band[a] = b;
        changed = true;
      };
      t = this.Tier(a);
      if t != this.m_tier[a] {
        if this.m_tier[a] >= 0 && t > this.m_tier[a] {
          worse = ChromeArea.Name(a) + " " + (t == 2 ? "FAILING" : "worn") + " (" + IntToString(Cast<Int32>(this.cond[a])) + " %): " + ChromeArea.Symptom(a);
          this.Log("tier " + ChromeArea.Name(a) + " -> " + IntToString(t) + " at " + FloatToStringPrec(this.cond[a], 1) + " %");
        };
        this.m_tier[a] = t;
        changed = true;
      };
      a += 1;
    };
    if changed {
      this.ApplyPenalties();
    };
    if StrLen(worse) > 0 && IsDefined(s) && s.notices {
      this.Notice("Chrome: " + worse + ". See a ripperdoc.", SimpleMessageType.Negative);
    };
  }

  private final func AddMod(stat: gamedataStatType, type: gameStatModifierType, value: Float) -> Void {
    let m: ref<gameStatModifierData> = RPGManager.CreateStatModifier(stat, type, value);
    if GameInstance.GetStatsSystem(this.GetGameInstance()).AddModifier(Cast<StatsObjectID>(this.m_player.GetEntityID()), m) {
      ArrayPush(this.m_mods, m);
    };
  }

  // 1.7.0 build 2 (review 2c, A): stats used as x (1 + value) without a floor (regen rate mults, buff duration).
  // Own penalty capped at cap, and never pushes the total (other mods' modifiers, e.g. Dark Future dehydration
  // -0.5 stamina regen, read with this mod's own removed) below floor.
  private final func AddScaleMod(stat: gamedataStatType, value: Float, cap: Float, floor: Float) -> Void {
    let others: Float = GameInstance.GetStatsSystem(this.GetGameInstance()).GetStatValue(Cast<StatsObjectID>(this.m_player.GetEntityID()), stat);
    let v: Float = MinF(0.0, MaxF(MaxF(value, cap), floor - others));
    if v < 0.0 {
      this.AddMod(stat, gameStatModifierType.Additive, v);
    };
    ArrayPush(this.m_scaleStat, stat);
    ArrayPush(this.m_scaleOthers, others);
    ArrayPush(this.m_scaleOwn, v < 0.0 ? v : 0.0);
  }

  // 1.7.2: rebuild when another mod's modifier on a floored stat appeared or ended since the last build
  private final func CheckScaleDrift() -> Void {
    let stats: ref<StatsSystem>;
    let id: StatsObjectID;
    let i: Int32 = 0;
    let now: Float;
    if !IsDefined(this.m_player) || ArraySize(this.m_scaleStat) == 0 {
      return;
    };
    stats = GameInstance.GetStatsSystem(this.GetGameInstance());
    id = Cast<StatsObjectID>(this.m_player.GetEntityID());
    while i < ArraySize(this.m_scaleStat) {
      now = stats.GetStatValue(id, this.m_scaleStat[i]) - this.m_scaleOwn[i];
      if AbsF(now - this.m_scaleOthers[i]) > 0.02 {
        this.Log("other modifiers on " + EnumValueToString("gamedataStatType", Cast<Int64>(EnumInt(this.m_scaleStat[i]))) + " moved " + FloatToStringPrec(this.m_scaleOthers[i], 2) + " -> " + FloatToStringPrec(now, 2) + ": penalties rebuilt");
        this.ApplyPenalties();
        return;
      };
      i += 1;
    };
  }

  public final func ApplyPenalties() -> Void {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let stats: ref<StatsSystem> = GameInstance.GetStatsSystem(this.GetGameInstance());
    let id: StatsObjectID;
    let i: Int32 = 0;
    let f: Float;
    let k: Float;
    if !IsDefined(this.m_player) {
      return;
    };
    id = Cast<StatsObjectID>(this.m_player.GetEntityID());
    while i < ArraySize(this.m_mods) {
      stats.RemoveModifier(id, this.m_mods[i]);
      i += 1;
    };
    ArrayClear(this.m_mods);
    ArrayClear(this.m_scaleStat);
    ArrayClear(this.m_scaleOthers);
    ArrayClear(this.m_scaleOwn);
    if !IsDefined(s) || !s.wear || !s.penalties {
      return;
    };
    // 1.7.0: each penalty = full value at 0 % x Severity (0 from 80 % down to 1 at 0 %, 5 % steps) x Penalty strength.
    // Units copied from vanilla: *Reduction / *PercentBonus / *RegenRateMult are fractions (the weapon / regen
    // formulas multiply by 1 - value or 1 + value), CritChance is in points, multipliers floor at 0.2.
    k = Cast<Float>(s.penaltyStrength) / 100.0;
    this.m_strength = s.penaltyStrength;
    // Operating system: cooldowns (Sandevistan, Berserk) up to +90 %, up to +4 RAM per quickhack.
    f = this.Severity(ChromeArea.OS()) * k;
    if f > 0.0 {
      this.AddMod(gamedataStatType.CyberwareCooldownReduction, gameStatModifierType.Additive, -0.90 * f);
      this.AddMod(gamedataStatType.MemoryCostReduction, gameStatModifierType.Additive, -4.0 * f);
    };
    // Frontal cortex: RAM recovers up to 80 % slower.
    f = this.Severity(ChromeArea.Frontal()) * k;
    if f > 0.0 {
      this.AddScaleMod(gamedataStatType.MemoryRegenRateMult, -0.80 * f, -0.60, -0.85);
    };
    // Optics: calibration drift, up to -20 crit chance points and 60 % slower aim-down-sights.
    f = this.Severity(ChromeArea.Eyes()) * k;
    if f > 0.0 {
      this.AddMod(gamedataStatType.CritChance, gameStatModifierType.Additive, -20.0 * f);
      this.AddMod(gamedataStatType.ADSSpeedPercentBonus, gameStatModifierType.Additive, -0.60 * f);
    };
    // Circulatory: clogged pumps, up to 80 % slower stamina regen and 40 % less stamina.
    f = this.Severity(ChromeArea.Cardio()) * k;
    if f > 0.0 {
      this.AddScaleMod(gamedataStatType.StaminaRegenRateMult, -0.80 * f, -0.60, -0.85);
      this.AddMod(gamedataStatType.Stamina, gameStatModifierType.Multiplier, MaxF(0.2, 1.0 - 0.40 * f));
    };
    // Nervous system: Kerenzikov and other cyberware buffs end up to 80 % sooner.
    f = this.Severity(ChromeArea.Nervous()) * k;
    if f > 0.0 {
      this.AddScaleMod(gamedataStatType.CyberwareDurationBuff, -0.80 * f, -0.75, -0.90);
    };
    // Immune system: saturated filters, health regenerates up to 80 % slower.
    f = this.Severity(ChromeArea.Immune()) * k;
    if f > 0.0 {
      this.AddScaleMod(gamedataStatType.HealthGeneralRegenRateMult, -0.80 * f, -0.60, -0.85);
    };
    // Subdermal plating: up to 60 % less armor.
    f = this.Severity(ChromeArea.Skin()) * k;
    if f > 0.0 {
      this.AddMod(gamedataStatType.Armor, gameStatModifierType.Multiplier, MaxF(0.2, 1.0 - 0.60 * f));
    };
    // Skeleton: micro-fractured lacing carries up to 50 % less.
    f = this.Severity(ChromeArea.Skeleton()) * k;
    if f > 0.0 {
      this.AddMod(gamedataStatType.CarryCapacity, gameStatModifierType.Multiplier, MaxF(0.2, 1.0 - 0.50 * f));
    };
    // Arms: grinding actuators, every cyberarm swing costs up to 160 % more stamina.
    f = this.Severity(ChromeArea.Arms()) * k;
    if f > 0.0 {
      this.AddMod(gamedataStatType.StrongArmsStaminaCostReduction, gameStatModifierType.Additive, -1.6 * f);
      this.AddMod(gamedataStatType.MantisBladesStaminaCostReduction, gameStatModifierType.Additive, -1.6 * f);
      this.AddMod(gamedataStatType.MonoWiresStaminaCostReduction, gameStatModifierType.Additive, -1.6 * f);
    };
    // Hands: sticking servos, reloads up to 80 % slower, recoil up to 100 % stronger.
    f = this.Severity(ChromeArea.Hands()) * k;
    if f > 0.0 {
      this.AddMod(gamedataStatType.ReloadSpeedPercentBonus, gameStatModifierType.Additive, -0.80 * f);
      this.AddMod(gamedataStatType.RecoilPercentBonus, gameStatModifierType.Additive, -1.0 * f);
    };
    // Legs: slipping tendons, jumps up to 60 % lower.
    f = this.Severity(ChromeArea.Legs()) * k;
    if f > 0.0 {
      this.AddMod(gamedataStatType.JumpHeight, gameStatModifierType.Multiplier, MaxF(0.2, 1.0 - 0.60 * f));
    };
    if ArraySize(this.m_mods) > 0 {
      this.Log("penalties applied: " + IntToString(ArraySize(this.m_mods)) + " modifiers, strength " + IntToString(s.penaltyStrength) + " %");
    };
  }

  private final func ReapplyIfSettingsChanged() -> Void {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let on: Bool = IsDefined(s) && s.wear && s.penalties;
    if NotEquals(on, this.m_penaltiesOn) || (on && s.penaltyStrength != this.m_strength) {
      this.m_penaltiesOn = on;
      this.ApplyPenalties();
    };
  }

  // 1.7.0: worn chrome can glitch out when fired: chance = 60 minus the condition (50 %: 10 %, 30 %: 30 %),
  // below 10 % the system is dead and always fails.
  public final func MaybeMalfunction(a: Int32, what: String) -> Void {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let c: Float;
    let chance: Int32;
    if !IsDefined(s) || !s.wear || !s.malfunctions || !IsDefined(this.m_player) || !this.HasChrome(a) {
      return;
    };
    c = this.Condition(a);
    if c >= 60.0 {
      return;
    };
    chance = c < 10.0 ? 100 : Cast<Int32>(60.0 - c);
    if RandRange(0, 100) >= chance {
      return;
    };
    StatusEffectHelper.ApplyStatusEffect(this.m_player, t"AIQuickHackStatusEffect.HackCyberware");
    this.Log("malfunction " + ChromeArea.Name(a) + " on " + what + " at " + FloatToStringPrec(c, 1) + " % (chance " + IntToString(chance) + " %)");
    if s.notices {
      this.Notice(c < 10.0 ? "Chrome DEAD: " + ChromeArea.Name(a) + " won't fire (" + IntToString(Cast<Int32>(c)) + " %). See a ripperdoc." : "Chrome malfunction: " + ChromeArea.Name(a) + " glitched out (" + IntToString(Cast<Int32>(c)) + " %)", SimpleMessageType.Negative);
    };
  }

  public final func Notice(text: String, type: SimpleMessageType) -> Void {
    let msg: SimpleScreenMessage;
    msg.isShown = true;
    msg.duration = 5.0;
    msg.message = text;
    msg.isInstant = true;
    msg.type = type;
    GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_Notifications).SetVariant(GetAllBlackboardDefs().UI_Notifications.WarningMessage, ToVariant(msg), true);
  }

  // --- 1.5.0: nanobot canisters, the emergency field repair (prices and parts: ChromeRepair in CyberslopChromeRepair.reds).
  // One canister: every system below 50 % rises to 50 % over 60 game minutes, on the game clock (waiting and sleeping
  // count). The swarm rebuilds from feedstock: components of the implant's quality (or higher) from V's bag, twice what
  // a ripper would use for the same work. Short on components = a partial repair, worst system first.

  public final func NanoActive() -> Bool = this.nanoUntil > 0.0

  public final func NanoMinutesLeft() -> Float {
    if this.nanoUntil <= 0.0 {
      return 0.0;
    };
    return MaxF(0.0, (this.nanoUntil - this.GameNow()) / 60.0);
  }

  // % the running dose still has to add to system a.
  public final func NanoLeftFor(a: Int32) -> Float {
    this.Ensure();
    if a < 0 || a >= ChromeArea.Count() {
      return 0.0;
    };
    return this.nanoLeft[a];
  }

  public final func AddNanobots(n: Int32) -> Void {
    this.nanobots = Max(0, Min(ChromeRepair.NanoCarry(), this.nanobots + n));
  }

  // Moves the running dose up to the game clock. Safe to call any time (the CET window calls it too).
  public final func NanoUpdate() -> Void {
    let ceiling: Float = ChromeRepair.NanoCeiling();
    let now: Float;
    let upTo: Float;
    let dt: Float;
    let add: Float;
    let a: Int32 = 0;
    if this.nanoUntil <= 0.0 {
      return;
    };
    this.Ensure();
    now = this.GameNow();
    if now < this.nanoLast {
      this.nanoLast = now;
    };
    upTo = MinF(now, this.nanoUntil);
    dt = upTo - this.nanoLast;
    if dt > 0.0 {
      while a < ChromeArea.Count() {
        if this.nanoLeft[a] > 0.0 {
          add = MinF(this.nanoLeft[a], this.nanoRate[a] * dt);
          this.nanoLeft[a] = this.nanoLeft[a] - add;
          // Wear during the hour still counts; a ripper repair meanwhile is never pulled back down.
          if this.cond[a] < ceiling {
            this.cond[a] = MinF(ceiling, this.cond[a] + add);
          };
        };
        a += 1;
      };
      this.nanoLast = upTo;
    };
    if now >= this.nanoUntil {
      this.NanoFinish();
    };
  }

  private final func NanoFinish() -> Void {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let a: Int32 = 0;
    while a < ChromeArea.Count() {
      this.nanoLeft[a] = 0.0;
      this.nanoRate[a] = 0.0;
      a += 1;
    };
    this.nanoUntil = 0.0;
    this.nanoLast = 0.0;
    this.UpdateTiers(false);
    this.Log("nanobots done | " + this.Summary());
    if IsDefined(s) && s.notices {
      this.Notice("Nanobots spent, field repair finished: " + this.Summary(), SimpleMessageType.Neutral);
    };
  }

  // What a canister would do now (commit = false: dry run for the window) or does (commit = true).
  public final func NanoPlan(commit: Bool) -> ref<ChromeNanoPlan> {
    let gi: GameInstance = this.GetGameInstance();
    let plan: ref<ChromeNanoPlan> = new ChromeNanoPlan();
    let ceiling: Float = ChromeRepair.NanoCeiling();
    let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(gi);
    let avail: array<Int32>;
    let order: array<Int32>;
    let parts: array<ref<ChromePart>>;
    let a: Int32;
    let i: Int32;
    let j: Int32;
    let k: Int32;
    let n: Int32;
    let left: Int32;
    let t: Int32;
    let needSys: Int32;
    let gotSys: Int32;
    let delta: Float;
    let gain: Float;
    plan.Init();
    if !IsDefined(this.m_player) {
      return plan;
    };
    this.Ensure();
    this.RefreshCounts();
    avail = ChromeRepair.Inventory(gi, this.m_player);
    k = 0;
    while k < 5 {
      plan.have[k] = avail[k];
      k += 1;
    };
    a = 0;
    while a < ChromeArea.Count() {
      if this.HasChrome(a) && this.cond[a] < ceiling - 0.5 {
        ArrayPush(order, a);
      };
      a += 1;
    };
    // Worst first: the feedstock goes where the damage is.
    while ArraySize(order) > 0 {
      i = 0;
      j = 0;
      while i < ArraySize(order) {
        if this.cond[order[i]] < this.cond[order[j]] {
          j = i;
        };
        i += 1;
      };
      a = order[j];
      ArrayErase(order, j);
      delta = ceiling - this.cond[a];
      parts = ChromeRepair.Parts(gi, this.m_player, a);
      needSys = 0;
      gotSys = 0;
      i = 0;
      while i < ArraySize(parts) {
        n = ChromeRepair.Units(parts[i].base, parts[i].q, delta, ChromeRepair.NanoWaste());
        needSys += n;
        plan.need[parts[i].q] = plan.need[parts[i].q] + n;
        left = n;
        k = parts[i].q;
        while k < 5 && left > 0 {
          t = Min(left, avail[k]);
          avail[k] = avail[k] - t;
          plan.take[k] = plan.take[k] + t;
          left -= t;
          k += 1;
        };
        gotSys += n - left;
        i += 1;
      };
      gain = needSys > 0 ? delta * Cast<Float>(gotSys) / Cast<Float>(needSys) : delta;
      plan.systems += 1;
      if gain >= 0.5 {
        plan.gain[a] = gain;
        plan.total += gain;
        plan.text += (StrLen(plan.text) > 0 ? ", " : "") + ChromeArea.Name(a) + " " + IntToString(Cast<Int32>(this.cond[a])) + " -> " + IntToString(Cast<Int32>(this.cond[a] + gain)) + " %";
      } else {
        plan.text += (StrLen(plan.text) > 0 ? ", " : "") + ChromeArea.Name(a) + " " + IntToString(Cast<Int32>(this.cond[a])) + " % (no feedstock)";
      };
      if gotSys < needSys {
        plan.short = true;
      };
    };
    if !commit || plan.total < 0.5 {
      return plan;
    };
    k = 0;
    while k < 5 {
      if plan.take[k] > 0 {
        ts.RemoveItemByTDBID(this.m_player, ChromeRepair.CompID(k), plan.take[k], true);
      };
      k += 1;
    };
    a = 0;
    while a < ChromeArea.Count() {
      this.nanoLeft[a] = plan.gain[a];
      this.nanoRate[a] = plan.gain[a] / ChromeRepair.NanoSeconds();
      a += 1;
    };
    this.nanoLast = this.GameNow();
    this.nanoUntil = this.nanoLast + ChromeRepair.NanoSeconds();
    this.nanobots -= 1;
    return plan;
  }

  public final func InjectNanobots() -> String {
    let s: ref<ChromeUpkeepSettings> = this.Settings();
    let plan: ref<ChromeNanoPlan>;
    let msg: String;
    if !IsDefined(s) || !s.nanobots {
      return "Nanobot canisters are off (Mod Settings > Cyberslop Chrome Upkeep).";
    };
    if !IsDefined(this.m_player) {
      return "No player.";
    };
    this.NanoUpdate();
    if this.NanoActive() {
      return "Nanobots already at work: " + IntToString(Cast<Int32>(this.NanoMinutesLeft() + 0.5)) + " game min left.";
    };
    if this.nanobots <= 0 {
      return "No nanobot canister. Any ripperdoc sells them (" + ChromeRepair.Eddies(ChromeRepair.NanoPrice()) + " eddies).";
    };
    plan = this.NanoPlan(false);
    if plan.systems == 0 {
      return "Nothing below " + IntToString(Cast<Int32>(ChromeRepair.NanoCeiling())) + " %: nanobots only pull failing chrome back to " + IntToString(Cast<Int32>(ChromeRepair.NanoCeiling())) + " %. The rest is ripper work.";
    };
    if plan.total < 0.5 {
      return "No feedstock: the swarm needs " + ChromeRepair.UnitsText(plan.need) + " components (the implant's quality or higher), you have " + ChromeRepair.UnitsText(plan.have) + ".";
    };
    plan = this.NanoPlan(true);
    msg = "Nanobots injected: " + plan.text + " over 60 game min, fed on " + ChromeRepair.UnitsText(plan.take) + " components" + (plan.short ? " (not enough for all of it)" : "") + ". " + IntToString(this.nanobots) + (this.nanobots == 1 ? " canister" : " canisters") + " left.";
    this.Log(msg);
    if s.notices {
      this.Notice(msg, SimpleMessageType.Neutral);
    };
    this.m_gen += 1;
    this.Schedule(10.0);
    return msg;
  }

  // One line per system with chrome, for the Biomonitor window and the CET console.
  public final func Summary() -> String {
    let out: String = "";
    let a: Int32 = 0;
    this.RefreshCounts();
    while a < ChromeArea.Count() {
      if this.HasChrome(a) {
        out += ChromeArea.Name(a) + " " + IntToString(Cast<Int32>(this.cond[a])) + "%" + (this.Tier(a) == 2 ? " FAILING" : (this.Tier(a) == 1 ? " worn" : "")) + "; ";
      };
      a += 1;
    };
    return out;
  }
}

// ---------------------------------------------------------------- wear hooks (all call through)

public abstract class ChromeHooks {
  public static func Wear(gi: GameInstance, a: Int32, amount: Float, why: String) -> Void {
    let w: ref<ChromeWear> = ChromeWear.Get(gi);
    if IsDefined(w) {
      w.Wear(a, amount, why);
    };
  }

  public static func Fired(gi: GameInstance, a: Int32, amount: Float, why: String) -> Void {
    let w: ref<ChromeWear> = ChromeWear.Get(gi);
    if IsDefined(w) {
      w.MaybeMalfunction(a, why);
      w.Wear(a, amount, why);
    };
  }
}

@wrapMethod(UseSandevistanAction)
public func StartAction(gameInstance: GameInstance) -> Void {
  wrappedMethod(gameInstance);
  if IsDefined(this.GetExecutor()) && this.GetExecutor().IsPlayer() {
    ChromeHooks.Fired(gameInstance, ChromeArea.OS(), 0.9, "Sandevistan");
  };
}

@wrapMethod(UseBerserkAction)
public func StartAction(gameInstance: GameInstance) -> Void {
  wrappedMethod(gameInstance);
  if IsDefined(this.GetExecutor()) && this.GetExecutor().IsPlayer() {
    ChromeHooks.Fired(gameInstance, ChromeArea.OS(), 0.9, "Berserk");
  };
}

// Optical Camo and Blood Pump (the generic cyberware "Use" action).
@wrapMethod(UseAction)
public func StartAction(gameInstance: GameInstance) -> Void {
  let data: ref<gameItemData>;
  let kind: CName;
  wrappedMethod(gameInstance);
  data = this.GetItemData();
  if !IsDefined(data) || !IsDefined(this.GetExecutor()) || !this.GetExecutor().IsPlayer() {
    return;
  };
  kind = TweakDBInterface.GetCName(ItemID.GetTDBID(data.GetID()) + t".cyberwareType", n"None");
  if Equals(kind, n"OpticalCamo") {
    ChromeHooks.Wear(gameInstance, ChromeArea.Skin(), 0.8, "Optical Camo");
  } else {
    if Equals(kind, n"BloodPump") {
      ChromeHooks.Wear(gameInstance, ChromeArea.Cardio(), 0.8, "Blood Pump");
    };
  };
}

@wrapMethod(KerenzikovEvents)
protected func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void {
  wrappedMethod(stateContext, scriptInterface);
  ChromeHooks.Fired(scriptInterface.GetGame(), ChromeArea.Nervous(), 0.5, "Kerenzikov");
}

// Cyberarm swings: Gorilla Arms, Mantis Blades, Monowire.
@wrapMethod(MeleeAttackGenericEvents)
protected final func SpawnAttackGameEffect(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>, startPosition: Vector4, middlePosition: Vector4, endPosition: Vector4, time: Float, colliderBox: Vector4, attackData: ref<MeleeAttackData>) -> Bool {
  let ok: Bool = wrappedMethod(stateContext, scriptInterface, startPosition, middlePosition, endPosition, time, colliderBox, attackData);
  let weapon: ref<WeaponObject>;
  let rec: ref<Item_Record>;
  let type: gamedataItemType;
  if !ok || !IsDefined(scriptInterface.executionOwner as PlayerPuppet) {
    return ok;
  };
  weapon = scriptInterface.owner as WeaponObject;
  if !IsDefined(weapon) {
    return ok;
  };
  rec = TweakDBInterface.GetItemRecord(ItemID.GetTDBID(weapon.GetItemID()));
  if !IsDefined(rec) || !IsDefined(rec.ItemType()) {
    return ok;
  };
  type = rec.ItemType().Type();
  if Equals(type, gamedataItemType.Cyb_StrongArms) || Equals(type, gamedataItemType.Cyb_MantisBlades) || Equals(type, gamedataItemType.Cyb_NanoWires) {
    ChromeHooks.Wear(scriptInterface.GetGame(), ChromeArea.Arms(), 0.05, "arm swing");
  };
  return ok;
}

// Projectile Launcher shot (Intuitive Projectile Launcher System replaces the body; wraps still run).
@wrapMethod(LeftHandCyberwareTransition)
public final func DetachProjectile(scriptInterface: ref<StateGameScriptInterface>, opt angleOffset: Float) -> Void {
  wrappedMethod(scriptInterface, angleOffset);
  if IsDefined(scriptInterface.executionOwner as PlayerPuppet) {
    ChromeHooks.Wear(scriptInterface.GetGame(), ChromeArea.Arms(), 0.8, "launcher shot");
  };
}

// Double jump, charged jump, air dash (leg actuators and tendons).
@wrapMethod(LocomotionTransition)
protected final const func LogSpecialMovementToTelemetry(const scriptInterface: ref<StateGameScriptInterface>, mvtType: telemetryMovementType) -> Void {
  wrappedMethod(scriptInterface, mvtType);
  if Equals(mvtType, telemetryMovementType.DoubleJump) || Equals(mvtType, telemetryMovementType.ChargedJump) || Equals(mvtType, telemetryMovementType.AirDodge) {
    if IsDefined(scriptInterface.executionOwner as PlayerPuppet) {
      ChromeHooks.Wear(scriptInterface.executionOwner.GetGame(), ChromeArea.Legs(), 0.06, "jump");
    };
  };
}

// Quickhack uploads (vanilla puts QuickHackUploaded on V for 0.15 s) and Overclock.
@wrapMethod(PlayerPuppet)
protected cb func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>) -> Bool {
  let r: Bool = wrappedMethod(evt);
  if IsDefined(evt) && IsDefined(evt.staticData) && evt.isNewApplication {
    if evt.staticData.GetID() == t"BaseStatusEffect.QuickHackUploaded" {
      ChromeHooks.Wear(this.GetGame(), ChromeArea.OS(), 0.12, "quickhack");
      ChromeHooks.Wear(this.GetGame(), ChromeArea.Frontal(), 0.05, "quickhack");
    } else {
      if ArrayContains(evt.staticData.GameplayTags(), n"Overclock") {
        ChromeHooks.Fired(this.GetGame(), ChromeArea.OS(), 0.6, "Overclock");
      };
    };
  };
  return r;
}

// Hits taken: subdermal plating and bone lacing soak them.
@wrapMethod(ScriptedPuppet)
protected cb func OnDamageReceived(evt: ref<gameDamageReceivedEvent>) -> Bool {
  let r: Bool = wrappedMethod(evt);
  let maxHP: Float;
  let pct: Float;
  if this.IsPlayer() && IsDefined(evt) && evt.totalDamageReceived > 0.0 {
    maxHP = GameInstance.GetStatsSystem(this.GetGame()).GetStatValue(Cast<StatsObjectID>(this.GetEntityID()), gamedataStatType.Health);
    if maxHP > 0.0 {
      pct = 100.0 * evt.totalDamageReceived / maxHP;
      ChromeHooks.Wear(this.GetGame(), ChromeArea.Skin(), 0.04 * pct, "hit");
      ChromeHooks.Wear(this.GetGame(), ChromeArea.Skeleton(), 0.015 * pct, "hit");
    };
  };
  return r;
}

// 1.7.1: the nervous-system penalty pushes CyberwareDurationBuff below 0 (floor -1 in ChromeUpkeepStatLimits.yaml).
// Vanilla time-dilation buffs (Synaptic Accelerator, Reflex Recorder) and StealthRunner's Grenade Spotter pick their
// slow-time effector with "CyberwareDurationBuff Equal 0" / "Greater 0", so a negative value matched neither and
// the slow time never started. At TweakDB load every such "Equal 0" stat prereq becomes "LessOrEqual 0": identical
// for values >= 0 (only this mod makes the stat negative), and worn chrome now gets the base slow time.
public class ChromeUpkeepDurationPrereqs extends ScriptableTweak {
  protected cb func OnApply() -> Void {
    let n: Int32 = 0;
    let st: String;
    let pr: ref<StatPrereq_Record>;
    for rec in TweakDBInterface.GetRecords(n"StatPrereq_Record") {
      pr = rec as StatPrereq_Record;
      if IsDefined(pr) && Equals(pr.ComparisonType(), n"Equal") && pr.ValueToCheck() == 0.0 && pr.GetStatModifiersCount() == 0 {
        st = NameToString(pr.StatType());
        if Equals(st, "CyberwareDurationBuff") || Equals(st, "BaseStats.CyberwareDurationBuff") {
          if TweakDBManager.SetFlat(pr.GetID() + t".comparisonType", n"LessOrEqual") {
            TweakDBManager.UpdateRecord(pr.GetID());
            n += 1;
          };
        };
      };
    };
    FTLog(s"[ChromeUpkeep] 1.7.1: \(n) CyberwareDurationBuff Equal-0 prereqs set to LessOrEqual 0 (slow time works on worn chrome)");
  }
}

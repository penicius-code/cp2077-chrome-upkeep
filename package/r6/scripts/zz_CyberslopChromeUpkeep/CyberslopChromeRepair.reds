// Cyberslop Chrome Upkeep 1.6.0 (2026-11-22): what a chrome repair costs, and the nanobot canisters.
// 1.6.0: the ripper uses the components in V's bag first (same quality as the implant) and only charges for the
//   ones V is missing, at market price ("Repairs use your components" in Mod Settings, on by default). Repair all /
//   the chair service share the bag, worst system first (ChromeClinic.PlanRepairs).
//
// RIPPER REPAIR (any ripperdoc, always to 100 %): materials + the ripper's fee, per body system.
//   Base price  = an implant's shop price without V's Street Cred discount (Cyberslop Cyberware Prices: class
//                 price x Plus tier, e.g. a Legendary class D 1.2M, a Rare class A 30k).
//   Materials   = 3 % of the base price per 100 % wear, bought as components of the implant's own quality
//                 at market price (Cyberslop Materials Economy, Street Cred 1: Common 25, Uncommon 50, Rare 120,
//                 Epic 300, Legendary 750). No discount on materials: the ripper passes the parts on at cost.
//                 Reference: real high-end prosthetics/implants cost about 2-5 % of their price a year in parts.
//   Fee         = 4 % of the base price per 100 % wear (at least 250), x0.75 street / x1.0 pro / x1.3 top clinic,
//                 minus Street Cred (0.6 x cred / 50: -60 % at cred 50, a name in the street gets a name's rate),
//                 Viktor another 15 % off (a friend's rate).
//   Time        = 10 min + 0.3 min per % of wear + 5 min per extra implant in the system.
//   Example (cred 50, Viktor): Legendary++ class D legs (1.38M) at 58 %: 24 Legendary components 18,000 +
//   fee 10,250 = 28,250 eddies; a Rare class A optic (30k) at 70 %: 3 Rare 360 + fee 160 = 520.
//
// NANOBOTS (CET window): a canister costs 70,000 at any ripperdoc, V carries up to 10. One canister pulls every
//   system below 50 % up to 50 % over 60 game minutes, feeding on 2x the ripper's components (the swarm is
//   wasteful) of the implant's quality or higher, taken from V's bag; short on components = partial, worst first.
module CyberslopChromeUpkeep

public class ChromePart extends IScriptable {
  public let base: Float;
  public let q: Int32;
}

public class ChromeQuote extends IScriptable {
  public let area: Int32;
  public let cond: Float;
  public let pieces: Int32;
  public let base: Int32;
  public let units: array<Int32>;
  public let partsText: String;
  // 1.6.0: components taken from V's bag (own) and bought from the ripper (units - own), per quality.
  public let own: array<Int32>;
  public let ownN: Int32;
  public let ownText: String;
  public let buyText: String;
  public let ownValue: Int32;   // market value of the bag components used (what V saves)
  public let matList: Int32;    // materials if every component were bought
  public let mat: Int32;        // materials V pays for (the missing components)
  public let feeList: Int32;
  public let fee: Int32;
  public let cut: Int32;
  public let total: Int32;
  public let minutes: Int32;
}

// 1.6.0: a run of repairs, worst system first, sharing V's bag and money (Repair all, the chair service, and
// the window's "Everything to 100" line). Systems V can't pay for are skipped; their components stay in the bag.
public class ChromeRepairPlan extends IScriptable {
  public let quotes: array<ref<ChromeQuote>>;
  public let count: Int32;
  public let total: Int32;
  public let mat: Int32;
  public let fee: Int32;
  public let minutes: Int32;
  public let own: array<Int32>;
  public let ownN: Int32;
  public let ownText: String;
  public let ownValue: Int32;
  public let skippedN: Int32;
  public let skipped: String;
}

public class ChromeNanoPlan extends IScriptable {
  public let systems: Int32;
  public let total: Float;
  public let short: Bool;
  public let text: String;
  public let need: array<Int32>;
  public let have: array<Int32>;
  public let take: array<Int32>;
  public let gain: array<Float>;

  public final func Init() -> Void {
    let i: Int32 = 0;
    while i < 5 {
      ArrayPush(this.need, 0);
      ArrayPush(this.have, 0);
      ArrayPush(this.take, 0);
      i += 1;
    };
    i = 0;
    while i < ChromeArea.Count() {
      ArrayPush(this.gain, 0.0);
      i += 1;
    };
  }

  public final func NeedText() -> String = ChromeRepair.UnitsText(this.need)
  public final func HaveText() -> String = ChromeRepair.UnitsText(this.have)
  public final func TakeText() -> String = ChromeRepair.UnitsText(this.take)
}

public abstract class ChromeRepair {

  public static func MatShare() -> Float = 0.03
  public static func FeeShare() -> Float = 0.04
  public static func MinFee() -> Float = 250.0
  public static func FriendCut() -> Float = 0.15
  public static func NanoWaste() -> Float = 2.0
  public static func NanoCeiling() -> Float = 50.0
  public static func NanoPrice() -> Int32 = 70000
  public static func NanoCarry() -> Int32 = 10
  public static func NanoSeconds() -> Float = 3600.0
  public static func Viktor() -> TweakDBID = t"Vendors.wat_lch_ripperdoc_01"

  // Component market price at Street Cred 1 (Cyberslop Materials Economy 1.0.0 price arrays).
  public static func CompPrice(q: Int32) -> Int32 {
    switch q {
      case 0: return 25;
      case 1: return 50;
      case 2: return 120;
      case 3: return 300;
    };
    return 750;
  }

  public static func CompID(q: Int32) -> TweakDBID {
    switch q {
      case 0: return t"Items.CommonMaterial1";
      case 1: return t"Items.UncommonMaterial1";
      case 2: return t"Items.RareMaterial1";
      case 3: return t"Items.EpicMaterial1";
    };
    return t"Items.LegendaryMaterial1";
  }

  public static func QName(q: Int32) -> String {
    switch q {
      case 0: return "Common";
      case 1: return "Uncommon";
      case 2: return "Rare";
      case 3: return "Epic";
    };
    return "Legendary";
  }

  public static func Eddies(v: Int32) -> String {
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

  public static func Round10(v: Float) -> Int32 {
    let n: Int32 = Cast<Int32>(v);
    if Cast<Float>(n) < v {
      n += 1;
    };
    return ((n + 9) / 10) * 10;
  }

  // "24 Legendary, 2 Epic" (highest first); "none" for all zero.
  public static func UnitsText(units: array<Int32>) -> String {
    let out: String = "";
    let q: Int32 = ArraySize(units) - 1;
    while q >= 0 {
      if units[q] > 0 {
        out += (StrLen(out) > 0 ? ", " : "") + IntToString(units[q]) + " " + ChromeRepair.QName(q);
      };
      q -= 1;
    };
    return StrLen(out) > 0 ? out : "none";
  }

  // Components of each quality in V's bag. 1.6.0: counted like the crafting screen (every stack of the record,
  // craftingSystem.swift GetItemQuantityWithDuplicates + CreateQuery).
  public static func Inventory(gi: GameInstance, player: ref<PlayerPuppet>) -> array<Int32> {
    let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(gi);
    let out: array<Int32>;
    let q: Int32 = 0;
    while q < 5 {
      ArrayPush(out, IsDefined(player) ? ts.GetItemQuantityWithDuplicates(player, ItemID.CreateQuery(ChromeRepair.CompID(q))) : 0);
      q += 1;
    };
    return out;
  }

  // Street Cred share off the ripper's fee: 0.6 x cred / 50.
  public static func CredCut(gi: GameInstance, player: ref<PlayerPuppet>) -> Float {
    let cred: Float;
    if !IsDefined(player) {
      return 0.0;
    };
    cred = GameInstance.GetStatsSystem(gi).GetStatValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatType.StreetCred);
    return 0.6 * ClampF(cred, 0.0, 50.0) / 50.0;
  }

  public static func StreetCred(gi: GameInstance, player: ref<PlayerPuppet>) -> Int32 {
    if !IsDefined(player) {
      return 0;
    };
    return RoundF(GameInstance.GetStatsSystem(gi).GetStatValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatType.StreetCred));
  }

  public static func FeeFactor(tier: Int32) -> Float {
    if tier <= 0 {
      return 0.75;
    };
    if tier >= 2 {
      return 1.3;
    };
    return 1.0;
  }

  // An implant's base price: the shop price with V's Street Cred discount taken back out
  // (Price.BuyPrice_StreetCred_Discount = -1 % per point of VendorBuyPriceDiscount).
  public static func BasePrice(gi: GameInstance, player: ref<PlayerPuppet>, id: ItemID) -> Float {
    let p: Float = Cast<Float>(RPGManager.CalculateBuyPrice(gi, player, id, 1.0));
    let disc: Float = GameInstance.GetStatsSystem(gi).GetStatValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatType.VendorBuyPriceDiscount);
    let f: Float = ClampF(1.0 - 0.01 * disc, 0.1, 1.0);
    if p <= 0.0 {
      return 20000.0;
    };
    return p / f;
  }

  // The implants installed in body system a: base price and quality (0 Common .. 4 Legendary; Plus tiers price in).
  public static func Parts(gi: GameInstance, player: ref<PlayerPuppet>, a: Int32) -> array<ref<ChromePart>> {
    let out: array<ref<ChromePart>>;
    let data: ref<EquipmentSystemPlayerData>;
    let area: gamedataEquipmentArea = ChromeArea.ToEquipmentArea(a);
    let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(gi);
    let item: wref<gameItemData>;
    let part: ref<ChromePart>;
    let id: ItemID;
    let n: Int32;
    let i: Int32 = 0;
    if !IsDefined(player) {
      return out;
    };
    data = EquipmentSystem.GetData(player);
    if !IsDefined(data) {
      return out;
    };
    n = data.GetNumberOfSlots(area, false);
    while i < n {
      id = data.GetItemInEquipSlot(area, i);
      if ItemID.IsValid(id) {
        part = new ChromePart();
        part.base = ChromeRepair.BasePrice(gi, player, id);
        item = ts.GetItemData(player, id);
        part.q = IsDefined(item) ? Max(0, Min(4, RoundF(item.GetStatValueByType(gamedataStatType.Quality)))) : 2;
        ArrayPush(out, part);
      };
      i += 1;
    };
    return out;
  }

  // Components of the implant's quality for pct % of wear (waste 1 = a ripper's bench, 2 = nanobots).
  public static func Units(base: Float, q: Int32, pct: Float, waste: Float) -> Int32 {
    let x: Float;
    let n: Int32;
    if pct <= 0.0 || base <= 0.0 {
      return 0;
    };
    x = base * pct / 100.0 * ChromeRepair.MatShare() * waste / Cast<Float>(ChromeRepair.CompPrice(q));
    n = Cast<Int32>(x);
    if Cast<Float>(n) < x {
      n += 1;
    };
    return n;
  }

  public static func UnitsSum(units: array<Int32>) -> Int32 {
    let n: Int32 = 0;
    let i: Int32 = 0;
    while i < ArraySize(units) {
      n += units[i];
      i += 1;
    };
    return n;
  }

  // Market value of a set of components (Street Cred 1 prices).
  public static func UnitsValue(units: array<Int32>) -> Int32 {
    let v: Int32 = 0;
    let i: Int32 = 0;
    while i < ArraySize(units) {
      v += units[i] * ChromeRepair.CompPrice(i);
      i += 1;
    };
    return v;
  }

  // 1.6.0: take the components a repair used out of V's bag (the counts come from a quote made on the current bag),
  // removed like crafting does (RemoveItemByTDBID across every stack).
  public static func Take(gi: GameInstance, player: ref<PlayerPuppet>, units: array<Int32>) -> Bool {
    let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(gi);
    let ok: Bool = true;
    let id: TweakDBID;
    let q: Int32 = 0;
    if !IsDefined(player) {
      return false;
    };
    while q < ArraySize(units) && q < 5 {
      if units[q] > 0 {
        id = ChromeRepair.CompID(q);
        if ts.GetItemQuantityWithDuplicates(player, ItemID.CreateQuery(id)) < units[q] || !ts.RemoveItemByTDBID(player, id, units[q], true) {
          ok = false;
        };
      };
      q += 1;
    };
    return ok;
  }

  // A ripper's quote for body system a at condition cond: tier 0 street / 1 pro / 2 top, friend = Viktor.
  // 1.6.0: bag = components V has per quality (empty = buy everything); the ripper uses those of the implant's own
  // quality first and charges market price only for the rest. The bag itself is not changed here.
  public static func Quote(gi: GameInstance, player: ref<PlayerPuppet>, a: Int32, cond: Float, tier: Int32, friend: Bool, pricePct: Int32, bag: array<Int32>) -> ref<ChromeQuote> {
    let q: ref<ChromeQuote> = new ChromeQuote();
    let parts: array<ref<ChromePart>>;
    let buy: array<Int32>;
    let wear: Float = ClampF(100.0 - cond, 0.0, 100.0);
    let scale: Float = Cast<Float>(Max(1, pricePct)) / 100.0;
    let base: Float = 0.0;
    let mat: Float = 0.0;
    let matList: Float = 0.0;
    let feeList: Float;
    let fee: Float;
    let n: Int32;
    let i: Int32 = 0;
    while i < 5 {
      ArrayPush(q.units, 0);
      ArrayPush(q.own, 0);
      ArrayPush(buy, 0);
      i += 1;
    };
    q.area = a;
    q.cond = cond;
    parts = ChromeRepair.Parts(gi, player, a);
    q.pieces = ArraySize(parts);
    i = 0;
    while i < ArraySize(parts) {
      base += parts[i].base;
      n = ChromeRepair.Units(parts[i].base, parts[i].q, wear, 1.0);
      q.units[parts[i].q] = q.units[parts[i].q] + n;
      i += 1;
    };
    q.base = RoundF(base);
    q.partsText = ChromeRepair.UnitsText(q.units);
    q.ownText = "none";
    q.buyText = q.partsText;
    if wear < 0.5 || q.pieces == 0 {
      return q;
    };
    i = 0;
    while i < 5 {
      q.own[i] = i < ArraySize(bag) ? Max(0, Min(q.units[i], bag[i])) : 0;
      buy[i] = q.units[i] - q.own[i];
      matList += Cast<Float>(q.units[i] * ChromeRepair.CompPrice(i));
      mat += Cast<Float>(buy[i] * ChromeRepair.CompPrice(i));
      i += 1;
    };
    q.ownN = ChromeRepair.UnitsSum(q.own);
    q.ownText = ChromeRepair.UnitsText(q.own);
    q.buyText = ChromeRepair.UnitsText(buy);
    q.ownValue = ChromeRepair.Round10(Cast<Float>(ChromeRepair.UnitsValue(q.own)) * scale);
    feeList = MaxF(ChromeRepair.MinFee(), base * wear / 100.0 * ChromeRepair.FeeShare()) * ChromeRepair.FeeFactor(tier) * scale;
    fee = feeList * (1.0 - ChromeRepair.CredCut(gi, player)) * (friend ? 1.0 - ChromeRepair.FriendCut() : 1.0);
    q.matList = ChromeRepair.Round10(matList * scale);
    q.mat = ChromeRepair.Round10(mat * scale);
    q.feeList = ChromeRepair.Round10(feeList);
    q.fee = ChromeRepair.Round10(fee);
    q.cut = feeList > 0.0 ? RoundF(100.0 * (1.0 - fee / feeList)) : 0;
    q.total = q.mat + q.fee;
    q.minutes = RoundF(10.0 + 0.3 * wear + 5.0 * Cast<Float>(q.pieces - 1));
    return q;
  }
}

/// Which fullscreen apps keep ⌥+clicks to themselves: games only. A fullscreen browser or video
/// player still gets pings.
public enum GameDetection {
  /// `category` is the app's LSApplicationCategoryType (e.g. "public.app-category.games",
  /// "public.app-category.action-games"). Riot's apps count regardless of what they declare.
  public static func isGame(bundleID: String?, category: String?) -> Bool {
    if let bundleID, bundleID.hasPrefix("com.riotgames.") { return true }
    return category?.hasSuffix("games") ?? false
  }
}

import Foundation

/// Your Supabase project (Project Settings → API). The anon key is meant to be public: what each
/// person can read or change is enforced by the row-level security rules in supabase/schema.sql.
/// Leave empty to turn accounts and in-app sharing off.
enum SocialConfig {
    static let supabaseURL = ""
    static let anonKey = ""

    static var isConfigured: Bool { !supabaseURL.isEmpty && !anonKey.isEmpty }
}

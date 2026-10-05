import Foundation

/// Your Supabase project (Project Settings → API). The anon key is meant to be public: what each
/// person can read or change is enforced by the row-level security rules in supabase/schema.sql.
/// Leave empty to turn accounts and in-app sharing off.
enum SocialConfig {
    static let supabaseURL = "https://fnnpicvcvonmnwkijlwc.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZubnBpY3Zjdm9ubW53a2lqbHdjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEyMjg5ODcsImV4cCI6MjEwNjgwNDk4N30.i0OO9XU6A9lyZjpqekJHFkabD7fdylDqef5YecDVzBk"

    static var isConfigured: Bool { !supabaseURL.isEmpty && !anonKey.isEmpty }
}

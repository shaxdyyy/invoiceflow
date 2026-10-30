import { createClient, type SupabaseClient } from '@supabase/supabase-js';
let instance: SupabaseClient | undefined;
export const previewOnly=process.env.NEXT_PUBLIC_PREVIEW_ONLY==='true';
export function browserDatabase() {
  if(previewOnly)return null;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) return null;
  instance ??= createClient(url, key);
  return instance;
}
export function requestDatabase(token: string) {
  if(previewOnly)throw new Error('This preview uses fictional demo data only.');
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) throw new Error('Database configuration is missing');
  return createClient(url, key, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false, autoRefreshToken: false } });
}

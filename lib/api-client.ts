import {browserDatabase} from './supabase';
export async function apiHeaders(){const token=(await browserDatabase()!.auth.getSession()).data.session?.access_token;if(!token)throw new Error('Sign in again.');return {'Content-Type':'application/json',Authorization:`Bearer ${token}`};}

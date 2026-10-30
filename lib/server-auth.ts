import { NextRequest } from 'next/server';
import { requestDatabase } from './supabase';
export async function authenticated(request:NextRequest){
 const origin=request.headers.get('origin');if(origin&&origin!==request.nextUrl.origin)throw new Error('Invalid request origin');
 const token=request.headers.get('authorization')?.replace(/^Bearer\s+/i,'');if(!token)throw new Error('Sign in to use the shared workspace.');
 const db=requestDatabase(token);const {data,error}=await db.auth.getUser(token);if(error||!data.user)throw new Error('Session expired. Sign in again.');
 return {db,user:data.user};
}

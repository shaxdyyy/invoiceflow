import { createCipheriv,createDecipheriv,createHash,randomBytes } from 'node:crypto';
import type { SupabaseClient } from '@supabase/supabase-js';
export const defaultModel='gemini-3.5-flash-lite';
export const allowedModels=['gemini-3.5-flash-lite','gemini-3.8-flash'];
function encryptionKey(){if(!process.env.REVIEW_SERVER_SECRET)throw new Error('Server encryption is not configured');return createHash('sha256').update(process.env.REVIEW_SERVER_SECRET).digest();}
export function encryptCredential(value:string){const iv=randomBytes(12);const cipher=createCipheriv('aes-256-gcm',encryptionKey(),iv);const encrypted=Buffer.concat([cipher.update(value,'utf8'),cipher.final()]);return [iv.toString('base64'),cipher.getAuthTag().toString('base64'),encrypted.toString('base64')].join('.');}
export function decryptCredential(value:string){const [iv,tag,encrypted]=value.split('.');const decipher=createDecipheriv('aes-256-gcm',encryptionKey(),Buffer.from(iv,'base64'));decipher.setAuthTag(Buffer.from(tag,'base64'));return Buffer.concat([decipher.update(Buffer.from(encrypted,'base64')),decipher.final()]).toString('utf8');}
export async function providerConfiguration(db:SupabaseClient){
 const {data,error}=await db.rpc('provider_configuration',{p_secret:process.env.REVIEW_SERVER_SECRET});
 if(error||!data?.encrypted_key||!data.cloud_ai_allowed)return null;
 return {apiKey:decryptCredential(data.encrypted_key),model:data.model||defaultModel};
}

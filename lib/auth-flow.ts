export const AUTH_REDIRECT_URL='https://invoiceflow-eight-omega.vercel.app/';
export function authMessage(error:unknown){
 const e=error as {code?:string;message?:string};const code=e?.code||'';
 if(code==='email_not_confirmed')return 'Your email is not confirmed yet. Open the newest confirmation email once, or use Resend confirmation below. Do not create the account again.';
 if(code==='otp_expired'||code==='otp_disabled'||/token.*(?:expired|invalid|not found)|link.*(?:expired|invalid)/i.test(e?.message||''))return 'This email link has expired or was already used. If you already confirmed your email, sign in with your password. Otherwise request a fresh confirmation below.';
 if(code==='over_email_send_rate_limit')return 'Supabase has temporarily reached its email-sending limit. Wait up to one hour before requesting another email. Repeated requests will not fix this. Existing confirmed accounts can still sign in.';
 if(code==='invalid_credentials')return 'The email or password is incorrect. Use the same email you registered with. If you forgot the password, choose Forgot password below. Confirmation does not create a new password.';
 if(code==='over_request_rate_limit'||code==='over_email_send_rate_limit'||code==='over_sms_send_rate_limit')return 'Too many attempts. Wait before trying again.';
 return e?.message||'Sign-in could not finish. Please try again.';
}
export function authReturn(href:string){
 const url=new URL(href),hash=new URLSearchParams(url.hash.replace(/^#/,''));
 const code=hash.get('error_code')||url.searchParams.get('error_code');
 const error=hash.get('error')||url.searchParams.get('error');
 const description=hash.get('error_description')||url.searchParams.get('error_description');
 return {message:(code||error||description)?authMessage({code:code||undefined,message:description||error||undefined}):'',recovery:hash.get('type')==='recovery'||url.searchParams.get('type')==='recovery',hasAuthData:['access_token','refresh_token','error','error_code','error_description','type'].some(k=>hash.has(k))||['code','error','error_code','error_description'].some(k=>url.searchParams.has(k))};
}
export function cleanAuthReturn(href:string){const url=new URL(href);for(const key of ['code','error','error_code','error_description','type','token','token_hash'])url.searchParams.delete(key);const hash=new URLSearchParams(url.hash.replace(/^#/,''));if(['access_token','refresh_token','error','error_description','error_code','type'].some(k=>hash.has(k)))url.hash='';return url.pathname+url.search+url.hash;}

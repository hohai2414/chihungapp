import React,{useEffect,useState} from 'react';
import {supabase} from './supabase.js';
export default function AuthGate({children}){
 const [session,setSession]=useState(null),[loading,setLoading]=useState(true),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 useEffect(()=>{
  if(!supabase){setLoading(false);return;}
  let mounted=true;
  const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,next)=>{if(mounted){setSession(next);setLoading(false);}});
  supabase.auth.getSession().then(({data,error})=>{if(mounted){if(error)setError(error.message);setSession(data.session);setLoading(false);}}).catch(e=>{if(mounted){setError(e.message);setLoading(false);}});
  return()=>{mounted=false;subscription.unsubscribe();};
 },[]);
 async function login(event){event.preventDefault();setBusy(true);setError('');const form=new FormData(event.currentTarget);try{const {error}=await supabase.auth.signInWithPassword({email:String(form.get('email')).trim(),password:String(form.get('password'))});if(error)throw error;}catch(e){setError(e.message);}finally{setBusy(false);}}
 if(loading)return <div className="auth-screen"><p>Đang kiểm tra phiên đăng nhập…</p></div>;
 if(!supabase)return <div className="auth-screen"><div className="auth-card"><h1>Chưa cấu hình kết nối</h1><p>Thêm VITE_SUPABASE_URL và VITE_SUPABASE_PUBLISHABLE_KEY trong Vercel rồi triển khai lại.</p></div></div>;
 if(session)return children(session.user);
 return <div className="auth-screen"><form className="auth-card" onSubmit={login}><span className="eyebrow">CHI HUNG · PEOPLEOPS</span><h1>Đăng nhập</h1><p>Sử dụng tài khoản đã được tạo trong Supabase.</p><label>Email<input name="email" type="email" autoComplete="username" required/></label><label>Mật khẩu<input name="password" type="password" autoComplete="current-password" required/></label>{error&&<p className="data-error" role="alert">{error}</p>}<button className="primary" disabled={busy}>{busy?'Đang đăng nhập…':'Đăng nhập'}</button></form></div>;
}

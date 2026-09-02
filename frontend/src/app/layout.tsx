import './globals.css';
import {ReactNode} from 'react';
export const metadata={title:'Nagode.io',description:'Payments and wallet platform'};
export default function Layout({children}:{children:ReactNode}){return <html lang="en"><body><header className="border-b border-slate-800 px-6 py-4"><div className="mx-auto max-w-6xl font-bold tracking-tight">Nagode<span className="gold">.io</span></div></header>{children}<footer className="mx-auto max-w-6xl px-6 py-10 text-sm text-slate-500">© 2025 Nagode.io. All rights reserved.</footer></body></html>}

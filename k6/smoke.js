import http from 'k6/http';
import {check} from 'k6';
export const options={vus:2,duration:'10s'};
export default function(){const base=__ENV.API_URL;if(!base)return;const r=http.get(`${base}/actuator/health`);check(r,{'health is 200':x=>x.status===200});}

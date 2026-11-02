from pathlib import Path
import os, subprocess
r=Path(__file__).resolve().parents[1];a=r/'src/user_source/hdl_source/advanced_curated';b=r/'tools/hdl_sim/mingw64/bin';t=r/'tests'
env=dict(os.environ);env['PATH']=str(b)+os.pathsep+env.get('PATH','')
import re
control_source=t/'record_controls_top.v'
control_source.write_text(re.sub(r'^`include.*$', '', (r/'src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf-8'),flags=re.M),encoding='utf-8')
for name,src,extra in [
 ('subtitle',[a/(x+'.v') for x in ['scrolling_subtitle','jiuzhaigou_font_rom','record_status_font']],[]),
 ('menu',[a/'status_osd_overlay.v'],[]),
 ('playback_select',[a/(x+'.v') for x in ['fat32_bmp_read','fat32_volume_scanner','fat32_file_streamer','fat32_bmp_stream_adapter','fat32_sector_bridge']],[]),
 ('controls',[control_source],['-i'])]:
 top='tb_record_'+name
 subprocess.run([str(b/'iverilog.exe'),'-g2012',*extra,'-s',top,'-o',str(t/(name+'.vvp')),str(t/(top+'.v')),*map(str,src)],cwd=t,env=env,check=True)
 subprocess.run([str(b/'vvp.exe'),str(t/(name+'.vvp'))],cwd=a if name=='subtitle' else t,env=env,check=True,timeout=20)

control_source.unlink(missing_ok=True)

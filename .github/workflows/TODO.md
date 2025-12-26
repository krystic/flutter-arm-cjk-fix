通过
ldd $(which <app name>) | grep libflutter_linux_gtk.so

获取 so 的绝对路径，再通过

strings /usr/share/rustdesk/lib/libflutter_linux_gtk.so.bak | grep -E "^[0-9a-f]{40}$"

获得 flutter engine 的 hash 值

然后通过以下脚本获取版本号和 hash 值的对应关系,：
./test.hash.sh

通过 cat flutter.engine.hash.verision | grep <hash> 获取版本号。
有时可能会获取到多个 hash 值，需要逐一比对版本号，找到正确的版本号

然后到仓库 raw 里查找是否有对应版本的编译版本 so
如果有，就下载替换掉 <app name> 里的 libflutter_linux_gtk.so ，做好原 so 文件备份
如果没有，就需要自己编译 flutter engine，编译方法见仓库 README.md

Lua 5.2/5.3, 跨平台

(Lua 5.1 请使用 https://github.com/asqbtcupid/lua_hotupdate )

(另外还可选择 https://github.com/jinq0123/hotfix
对模块加载初始化处理不同。)

接口包含
- HU.Init(ModuleNameOfUpdateList[, ENV])
- Update()

Init负责初始化。
ModuleNameOfUpdateList是一个lua模块名路径，
要求这个lua模块返回一个table，
这个table包含想要热更新的文件的文件名。例如：
```
-- 重新加载本模块以获取热更新模块名列表。
-- 可以任意动态添加或删除热更新模块。
local UpdateList = {
	"svc_login",
}
return UpdateList
```

Update每运行一次就对所列模块进行热更新，只更新函数，不更新数据。

请参考 asqbtcupid/lua_hotupdate （接口稍有区别）
详细配置[lua热更新](http://asqbtcupid.github.io/hotupdte-implement/)

![例子动图](https://raw.githubusercontent.com/asqbtcupid/asqbtcupid.github.com/master/images/hotupdate-example.gif)

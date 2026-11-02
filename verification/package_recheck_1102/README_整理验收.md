# 提交代码整理验收（2026-11-02）

采用10-26 TF冷启动恢复版，版本提交68880be6044b140cbe4e59483f408af77db256b4。已验证位流保持原文件；本次不下载或烧录板卡。

- 对整理目录内源码重新运行Icarus RTL维护回归：56/56通过。
- 对独立英文路径副本重新运行ModelSim 10.1d代表复核：12/12完成，无Error、Fatal或FAIL记录。各项完成标记保存在modelsim_12_cases.log。
- TD 6.2对独立目录生成的便携工程完成顶层展开、约束读取与Optimize RTL；记录含INDEPENDENT_PACKAGE_RTL_CHECK_PASS。该项是依赖完整性检查，不作为新一轮布局布线结果。
- 最终布局布线资源及时序结果引用verification/physical中与交付位流对应的原发布报告。
- 原始RTL、IP、字库、引脚及时序约束按来源清单核对；工程根路径元数据作便携处理。准备脚本只在build/portable_project生成路径适配副本，将5个字库INIT_FILE定位到同一字库数据；不改变业务逻辑。
- PACKAGE_MANIFEST.json记录复制文件来源，SHA256SUMS.txt覆盖本包全部交付文件（校验清单自身除外）。

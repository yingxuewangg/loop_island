import org.gradle.api.Project

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 有些 Flutter 插件把 compileSdk 写死在旧版本上（例如 file_picker 8.x 写死 34），
// 而当前 Flutter 默认已经是 36，且 flutter_plugin_android_lifecycle 明确要求
// 依赖它的模块至少编译到 36 —— 于是 `:file_picker:checkDebugAarMetadata` 直接失败。
//
// 这里统一把插件的 compileSdk 抬到与 Flutter 默认一致。等 file_picker 升级到
// 跟随 flutter.compileSdkVersion 的版本后，这段可以删掉。
//
// 两个注意点：
// 1. **必须放在 `evaluationDependsOn(":app")` 之前** —— 那一句会立刻触发插件子项目
//    的求值，之后注册的 `afterEvaluate` 会报 "project is already evaluated"。
// 2. 用反射而不是直接 cast 到 AGP 类型：根项目编译期没有 AGP 的 classpath，
//    而且 AGP 大版本之间这些类型名变动频繁，反射 + 多候选方法名更耐用。
val targetCompileSdk = 36

fun forceCompileSdk(project: Project) {
    val android = project.extensions.findByName("android") ?: return
    val methods = android.javaClass.methods
    val candidates = listOf("setCompileSdk", "setCompileSdkVersion", "compileSdkVersion")
    val applied = candidates.any { name ->
        val method = methods.firstOrNull {
            it.name == name &&
                it.parameterTypes.size == 1 &&
                (it.parameterTypes[0] == Int::class.javaPrimitiveType ||
                    it.parameterTypes[0] == Integer::class.java)
        }
        method != null && runCatching { method.invoke(android, targetCompileSdk) }.isSuccess
    }
    if (!applied) {
        project.logger.warn(
            "无法把 ${project.name} 的 compileSdk 提到 $targetCompileSdk；" +
                "若构建报 AAR metadata 版本不足，请手动处理该插件的 compileSdk。",
        )
    }
}

subprojects {
    if (state.executed) {
        forceCompileSdk(this)
    } else {
        afterEvaluate { forceCompileSdk(this) }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

package com.travelfootsteps.app

import io.flutter.embedding.android.FlutterFragmentActivity

// health 플러그인(Health Connect)이 액티비티를 androidx.activity.ComponentActivity로
// 캐스팅하므로 일반 FlutterActivity(ComponentActivity 미상속)로는 등록에 실패한다.
class MainActivity : FlutterFragmentActivity()

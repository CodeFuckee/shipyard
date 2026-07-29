import { FlutterPage } from '@ohos/flutter_ohos';

let storage = LocalStorage.getShared();

@Entry(storage)
@Component
struct Index {
  @LocalStorageLink('viewId') viewId: string = '';

  build() {
    Stack() {
      FlutterPage({ viewId: this.viewId })
    }
    .height('100%')
    .width('100%')
  }
}

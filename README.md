# ShibUI

## DESCRIPTION

'ShibUI' はHiveクエリについて日々の運用を行うためのツールです。以下のような機能があります。

* Hiveクエリの登録・実行、スケジュールに従っての実行
* クエリ結果のグラフ(HRForecast)への登録
* クエリ条件の選択によるHiveクエリの生成

主に定期的に実行したいクエリの管理・結果の可視化を行うために有用でしょう。クエリ生成はHiveクエリを直接書けない人が使う場合に便利かもしれません。

### EXCUSE

特定のHiveテーブルを対象にすることのみを考えて作ったものであるため、フル機能を他の環境で即座に使うことはできないと思います。特にクエリ生成機能などについては、手元のHiveテーブル定義にあわせてコードを変更する必要があります。(変更すべき箇所については後述します)

動作に以下のソフトウェアを必要とします。

* perl 5.14 以降
* MySQL 5.1 or 5.5

* shib (http://github.com/tagomoris/shib)
  * およびshibからアクセス可能なHadoop/Hiveクラスタ、Hive Server
  * Huahin Manager (http://huahinframework.org/huahin-manager/)
* HRForecast (https://github.com/kazeburo/HRForecast)

ShibUIはPerl用のアプリケーションサーバ Starlet 上で動作します。supervisord や daemontools などと組み合わせてデーモン化することをおすすめします。またユーザのリクエストを直接受けるのではなく、前に Apache や nginx などのリバースプロキシを入れることをおすすめします。(これは shib や HRForecast についても同様です。)

また ShibUI はクエリのスケジュールにOSの一般ユーザの crontab を使用します。crontab の更新を機械的に行われて問題がある場合、ShibUI専用のユーザアカウントを作り、そこで動作させるなどの対策が必要です。

なお ShibUI, shib, HRForecast はどれも特に大きな処理能力を必要としません。同一のホストで動作させても問題ないと思われます。

## SETUP

HadoopクラスタおよびHive ServerがHiveクエリを実行可能な状態で動作しているものとします。また Huahin Manager が動作していれば、クエリを実行中のMapReduceジョブの詳細な情報の取得やクエリの中断などが可能となります。Huahin Managerの使用は強くお薦めします。

### shib

shib を git://github.com/tagomoris/shib.git からcloneし、ドキュメントの通りにセットアップします。リバースプロキシサーバの設定なども可能ならすぐに行っておきます。クエリの実行と結果の表示・ダウンロードが可能かどうか確認しましょう。
また常に起動している必要があるので supervisord や daemontools 経由でのデーモン化をしておくと良いです。

### HRForecast

HRForecast を git://github.com/kazeburo/HRForecast.git からcloneし、セットアップします。現状セットアップ方法が書かれていませんが、以下のような感じでセットアップできるはずです。

1. perlbrew をインストールし `install-cpanm` した上で 5.14.x などの新しめのperlをインストールする
2. MySQL 5.1 or 5.5 あたりをインストールし、適当にデータベース名を決め schema.sql を mysql コマンドに流し込んでテーブルを作る
3. 依存モジュールをインストールする
   * `cpanm -n -Lextlib --installdeps .`
3. config.pl を更新する
4. hrforecast.pl を実行する
   * `perl -Ilib -Iextlib/lib/perl5 hrforecast.pl -c config.pl`

最後の hrforecast.pl の実行は shib と同じく daemonize tool 経由での実行をおすすめします。リバースプロキシの設定も行っておくと良いでしょう。画面の表示、データの登録、グラフの表示が正常に行えることを確認しておきます。

### ShibUI

perlbrew および MySQL を使えるようにセットアップしておく必要があります。

1. ShibUI を適当なディレクトリで clone する
  * `git clone git://github.com/tagomoris/shibui.git`
  * `cd shibui`
2. 依存モジュールをインストール
  * `cpanm -n -Lextlib --installdeps .`
  * CPANに上げてない依存モジュールがひとつあるので、それも
  * `curl -L -o Net-Hadoop-Hive-QueryBuilder.tar.gz https://github.com/tagomoris/Net-Hadoop-Hive-QueryBuilder/tarball/master`
  * `cpanm -n -Lextlib Net-Hadoop-Hive-QueryBuilder.tar.gz`
3. MySQLの設定を行う
  * データベース名を決めて create database し、適当なユーザにそのデータベースへのアクセス権限を付与する
  * 以下のコマンドで必要なテーブルを作成する
  * `mysql -H hostname -u username -p dbname < sql/create_tables.sql`
4. bin/env.sh および config.pl の各種設定を更新する
  * bin/env.sh を動作ホストの環境に従って更新する
   * USERNAME にShibUIを動作させるユーザ名を入れ `PERLBREW_BASHRC_PATH` に perlbrew を読み込むための bashrc スクリプトの場所を入れる
   * `LOG_DIR` に指定するディレクトリは mkdir してユーザの書き込み権限をつけておくこと
  * config.pl を動作環境にあわせて更新する
   * `host`/`port` はWebアプリケーションがlistenするIPアドレスおよびポートの指定
   * `front_proxy` にリバースプロキシサーバのIPアドレス(のリスト)を指定する
   * `allow_from` は直接きた接続を accept する対象のソースIPアドレス(or ネットワークアドレス)のリストを指定する
   * `dsn`/`db_username`/`db_password` はMySQLへの接続時の情報
   * shib 以下の `host` には shib へアクセスする際のホスト名、`support_huahin` は Huahin Manager が使用できれば 1 を、そうでなければ 0 を指定
   * hrforecast 以下の `host` には HRForecast へアクセスする際のホスト名
5. 起動
  * 手で起動してWebアプリケーション部分が正常に動作するか確認する
  * `perl -Iextlib/lib/perl5 -Ilib shibui.pl -c config.pl`
6. 本番環境での起動
  * `bin/start_shibui.sh` 経由で起動すると `PLACK_ENV=production` がセットされるので、本番環境ではこれを使うと良い
  * 本番環境用の設定を分けたい場合は bin/env.production.sh および production.pl としてファイルを置く
7. crontab に ShibUI 用の行を追加する
  * これは他の動作確認の完了後に実施
  * `crontab -l > crontab.tmp`
  * `cat crontab.tmp etc/cron.d/shibui-watcher etc/cron.d/shibui-queries | crontab -`

## CUSTOMIZE

### 表示について

社内事情を反映した内容にページを差し替えたい(典型的には index や docs)場合、設定で別のファイルを指定することで可能です。ただし views 以下のファイル名で指定してください。他の場所に置いてあるものに対しての symlink を置いておくと良いでしょう。

### クエリ生成について

クエリ生成は以下のようなテーブル定義に依存しています(保存フォーマットは省略)。またUserAgentまわりの判定を行う節は [Woothee](https://github.com/tagomoris/woothee) の Hive UDF が使えることが前提です。

    -- 通常時にクエリ対象として選択されるテーブル
    CREATE TABLE access_log (
       hhmmss STRING, -- 時分秒
       vhost STRING,
       path STRING,
       method STRING,
       status SMALLINT,
       bytes BIGINT,
       duration BIGINT, -- リクエスト処理時間(マイクロ秒)
       referer STRING,
       rhost STRING,
       userlabel STRING, -- ユーザ識別用ラベル(Cookieや携帯端末IDから生成したハッシュ値)
       agent STRING
    )
    PARTITIONED BY (service STRING, yyyymmdd STRING);
    
    -- 「今日」を選んだときにクエリ対象として選択されるテーブル
    -- データの内容は access_log と同様でパーティションの切りかたが時間毎
    CREATE TABLE hourly_log (
       hhmmss STRING,
       vhost STRING,
       path STRING,
       method STRING,
       status SMALLINT,
       bytes BIGINT,
       duration BIGINT,
       referer STRING,
       rhost STRING,
       userlabel STRING,
       agent STRING
    )
    PARTITIONED BY (service STRING, yyyymmddhh STRING);

[Woothee](https://github.com/tagomoris/woothee) の Hive UDF は以下のようにしてセットアップします。

 * Hive Server を起動するサーバに woothee.jar を置き、CLASSPATHにそのパスを含めた状態で起動する
 * shib の設定ファイルの setup_queries セクションを以下のように設定する

設定は shib の設定ファイル config.js で行います。

    hiveserver: {
      host: 'your.hive.server.local',
      port: 10000,
      support_database: true,
      default_database: 'default',
      setup_queries: [
        "add jar /home/USERNAME/PATH/TO/CLASSPATH/woothee.jar;",
        "create temporary function parse_agent as 'is.tagomor.woothee.hive.ParseAgent';",
        "create temporary function is_pc as 'is.tagomor.woothee.hive.IsPC';",
        "create temporary function is_smartphone as 'is.tagomor.woothee.hive.IsSmartPhone';",
        "create temporary function is_mobilephone as 'is.tagomor.woothee.hive.IsMobilePhone';",
        "create temporary function is_appliance as 'is.tagomor.woothee.hive.IsAppliance';",
        "create temporary function is_crawler as 'is.tagomor.woothee.hive.IsCrawler';",
        "create temporary function is_misc as 'is.tagomor.woothee.hive.IsMisc';",
        "create temporary function is_unknown as 'is.tagomor.woothee.hive.IsUnknown';",
        "create temporary function is_in as 'is.tagomor.woothee.hive.IsIn';",
        "create temporary function pc as 'is.tagomor.woothee.hive.PC';",
        "create temporary function smartphone as 'is.tagomor.woothee.hive.SmartPhone';",
        "create temporary function mobilephone as 'is.tagomor.woothee.hive.MobilePhone';",
        "create temporary function appliance as 'is.tagomor.woothee.hive.Appliance';",
        "create temporary function crawler as 'is.tagomor.woothee.hive.Crawler';",
        "create temporary function misc as 'is.tagomor.woothee.hive.Misc';",
        "create temporary function unknown as 'is.tagomor.woothee.hive.Unknown';",
        "create temporary function oneof as 'is.tagomor.woothee.hive.OneOf';"
      ]
    },

これらのテーブル定義およびUDFに対するクエリを発行するための定義が `Shib::ShibUI::QueryUtil` にあります。これらは Hive クエリのS式表現を生成し、最終的にそれが `Net::Hadoop::Hive::QueryBuilder` により変換されて Hive クエリとなります。環境に特有の UDF の定義などは QueryBuilder のインスタンス生成時に渡すこととなっており、それが `Shib::ShibUI::Web` の先頭にある `query_builder` 関数で定義されています。
クエリ生成に渡す条件はすべて HTML ビュー上で動的生成されており `views/query_builder.tx` および `public/js/shibui_querybuilder.js` でアイテムの定義などが行われています。

それぞれの環境向けにフルスペックで使用するためには、上記 HTML/js/perl にかなり手を入れる必要があります。気合いを入れて頑張ってください。

* * * * *

## License

Copyright 2012- TAGOMORI Satoshi (tagomoris)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.



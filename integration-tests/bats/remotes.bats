#!/usr/bin/env bats
load $BATS_TEST_DIRNAME/helper/common.bash

remotesrv_pid=
setup() {
    skiponwindows "tests are flaky on Windows"
    setup_common
    cd $BATS_TMPDIR
    mkdir remotes-$$
    mkdir remotes-$$/empty
    echo remotesrv log available here $BATS_TMPDIR/remotes-$$/remotesrv.log
    remotesrv --http-port 1234 --dir ./remotes-$$ &> ./remotes-$$/remotesrv.log 3>&- &
    remotesrv_pid=$!
    cd dolt-repo-$$
    mkdir "dolt-repo-clones"
}

teardown() {
    teardown_common
    kill $remotesrv_pid
    rm -rf $BATS_TMPDIR/remotes-$$
}

@test "remotes: dolt remotes server is running" {
    ps -p $remotesrv_pid | grep remotesrv
}

@test "remotes: pull also fetches" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add origin file://../remote
    dolt push origin main

    cd ..
    dolt clone file://./remote repo2

    cd repo2
    run dolt branch -va
    [[ "$output" =~ "main" ]] || false
    [[ ! "$output" =~ "other" ]] || false

    cd ../repo1
    dolt checkout -b other
    dolt push origin other

    cd ../repo2
    dolt pull
    run dolt branch -va
    [[ "$output" =~ "main" ]] || false
    [[ "$output" =~ "other" ]] || false
}

@test "remotes: pull also fetches, but does not merge other branches" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add origin file://../remote
    dolt push --set-upstream origin main
    dolt checkout -b other
    dolt commit --allow-empty -m "first commit on other"
    dolt push --set-upstream origin other

    cd ..
    dolt clone file://./remote repo2

    cd repo2
    run dolt pull
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Everything up-to-date." ]] || false

    dolt commit --allow-empty -m "a commit for main from repo2"
    dolt push

    run dolt branch
    [[ ! "$output" =~ "other" ]] || false

    run dolt checkout other
    [ "$status" -eq 0 ]
    [[ "$output" =~ "branch 'other' set up to track 'origin/other'." ]] || false

    run dolt log --oneline -n 1
    [ "$status" -eq 0 ]
    [[ "$output" =~ "first commit on other" ]] || false

    run dolt status
    [[ "$output" =~ "Your branch is up to date with 'origin/other'." ]] || false

    dolt commit --allow-empty -m "second commit on other from repo2"
    dolt push

    cd ../repo1
    dolt checkout other
    run dolt pull
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Updating" ]] || false

    run dolt log --oneline -n 1
    [ "$status" -eq 0 ]
    [[ "$output" =~ "second commit on other from repo2" ]] || false

    dolt checkout main
    run dolt status
    [[ "$output" =~ "behind 'origin/main' by 1 commit" ]] || false

    run dolt log --oneline -n 1
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "a commit for main from repo2" ]] || false

    run dolt pull
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Updating" ]] || false

    run dolt log --oneline -n 1
    [ "$status" -eq 0 ]
    [[ "$output" =~ "a commit for main from repo2" ]] || false
}

@test "remotes: cli 'dolt checkout new_branch' without -b flag creates new branch and sets upstream if there is a remote branch with matching name" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add origin file://../remote
    dolt push origin main
    dolt checkout -b other
    dolt push --set-upstream origin other

    cd ..
    dolt clone file://./remote repo2

    cd repo2
    dolt commit --allow-empty -m "a commit for main from repo2"
    dolt push
    run dolt branch
    [[ ! "$output" =~ "other" ]] || false

    run dolt checkout other
    [ "$status" -eq 0 ]
    [[ "$output" =~ "branch 'other' set up to track 'origin/other'." ]] || false

    run dolt status
    [[ "$output" =~ "Your branch is up to date with 'origin/other'." ]] || false
}

@test "remotes: guessing the remote branch fails if there are multiple remotes with branches with matching name" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add origin file://../remote
    dolt push origin main
    dolt checkout -b other
    dolt push origin other

    cd ..
    dolt clone file://./remote repo2

    cd repo2
    dolt remote add test-remote file://../remote
    dolt push test-remote main
    dolt checkout -b other
    dolt push test-remote other
    dolt branch -a
    dolt checkout main
    dolt branch -d other
    run dolt branch
    [[ ! "$output" =~ "other" ]] || false

    run dolt checkout other
    [ "$status" -eq 1 ]
    [[ "$output" =~ "'other' matched multiple (2) remote tracking branches" ]] || false
}

@test "remotes: cli 'dolt checkout -b new_branch' should not set upstream if there is a remote branch with matching name" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add origin file://../remote
    dolt sql -q "CREATE TABLE a (pk int)"
    dolt add .
    dolt commit -am "add table a"
    dolt push --set-upstream origin main
    dolt checkout -b other
    dolt push --set-upstream origin other

    cd ..
    dolt clone file://./remote repo2

    cd repo2
    dolt branch
    [[ ! "$output" =~ "other" ]] || false

    run dolt checkout -b other
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "branch 'other' set up to track 'origin/other'." ]] || false

    run dolt status
    [[ ! "$output" =~ "Your branch is up to date with 'origin/other'." ]] || false

    cd ../repo1
    dolt checkout other
    dolt sql -q "INSERT INTO a VALUES (1), (2)"
    dolt commit -am "add table a"
    dolt push

    cd ../repo2
    dolt checkout other
    run dolt pull
    [ "$status" -eq 1 ]
    [[ "$output" =~ "There is no tracking information for the current branch." ]] || false
}

@test "remotes: select DOLT_CHECKOUT('new_branch') without '-b' sets upstream if there is a remote branch with matching name" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt sql -q "CREATE TABLE test (pk INT)"
    dolt add .
    dolt commit -am "main commit"
    dolt push test-remote main
    run dolt branch -a
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "remotes/test-remote/test-branch" ]] || false

    cd ..
    dolt clone --remote=test-remote http://localhost:50051/test-org/test-repo repo2
    run dolt branch -a
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "test-branch" ]] || false
    [[ ! "$output" =~ "remotes/test-remote/test-branch" ]] || false

    cd repo1
    dolt checkout -b test-branch
    dolt sql -q "INSERT INTO test VALUES (1);"
    dolt commit -am "test commit"
    dolt push test-remote test-branch

    cd ../repo2
    dolt fetch test-remote
    run dolt branch
    [[ ! "$output" =~ "test-branch" ]] || false

    run dolt sql << SQL
SELECT DOLT_CHECKOUT('test-branch');
SELECT * FROM test;
SELECT DOLT_PULL();
SQL
    [ "$status" -eq 0 ]
    [[ "$output" =~ "pk" ]] || false
    [[ "$output" =~ "1" ]] || false

    run dolt branch
    [[ "$output" =~ "test-branch" ]] || false

    dolt checkout test-branch
    run dolt status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Your branch is up to date with 'test-remote/test-branch'." ]] || false
}

@test "remotes: select 'DOLT_CHECKOUT('-b','new_branch') should not set upstream if there is a remote branch with matching name" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add origin file://../remote
    dolt sql -q "CREATE TABLE a (pk int)"
    dolt add .
    dolt commit -am "add table a"
    dolt push --set-upstream origin main
    dolt checkout -b other
    dolt push --set-upstream origin other

    cd ..
    dolt clone file://./remote repo2

    cd repo2
    dolt branch
    [[ ! "$output" =~ "other" ]] || false

    # Checkout with DOLT_CHECKOUT and confirm the table has the row added in the remote
    run dolt sql << SQL
SELECT DOLT_CHECKOUT('-b','other');
SELECT DOLT_PULL();
SQL
    [ "$status" -eq 1 ]
    [[ "$output" =~ "There is no tracking information for the current branch." ]] || false
}

@test "remotes: add a remote using dolt remote" {
    run dolt remote add test-remote http://localhost:50051/test-org/test-repo
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    run dolt remote -v
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test-remote" ]] || false
    run dolt remote add test-remote
    [ "$status" -eq 1 ]
    [[ "$output" =~ "usage:" ]] || false
}

@test "remotes: remove a remote" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    run dolt remote remove test-remote
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    run dolt remote -v
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "test-remote" ]] || false
    run dolt remote remove poop
    [ "$status" -eq 1 ]
    [[ "$output" =~ "unknown remote: 'poop'" ]] || false
}

@test "remotes: push and pull an unknown remote" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    run dolt push poop main
    [ "$status" -eq 1 ]
    [[ "$output" =~ "unknown remote" ]] || false
    run dolt pull poop
    [ "$status" -eq 1 ]
    [[ "$output" =~ "unknown remote" ]] || false
}

@test "remotes: push with only one argument" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    run dolt push test-remote
    [ "$status" -eq 1 ]
    [[ "$output" =~ "fatal: The current branch main has no upstream branch." ]] || false
    [[ "$output" =~ "To push the current branch and set the remote as upstream, use" ]] || false
    [[ "$output" =~ "dolt push --set-upstream test-remote main" ]] || false
}

@test "remotes: push and pull main branch from a remote" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    run dolt push --set-upstream test-remote main
    [ "$status" -eq 0 ]
    [ -d "$BATS_TMPDIR/remotes-$$/test-org/test-repo" ]
    run dolt pull test-remote
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Everything up-to-date" ]] || false
}

@test "remotes: push and pull non-main branch from remote" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt checkout -b test-branch
    run dolt push --set-upstream test-remote test-branch
    [ "$status" -eq 0 ]
    run dolt pull test-remote
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Everything up-to-date" ]] || false
}

@test "remotes: pull with explicit remote and branch" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt checkout -b test-branch
    dolt sql -q "create table t1(c0 varchar(100));"
    dolt add .
    dolt commit -am "adding table t1"
    run dolt push test-remote test-branch
    [ "$status" -eq 0 ]
    dolt checkout main
    run dolt sql -q "show tables"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "t1" ]] || false

    # Specifying a non-existent remote branch returns an error
    run dolt pull test-remote doesnotexist
    [ "$status" -eq 1 ]
    [[ "$output" =~ 'branch "doesnotexist" not found on remote' ]] || false

    # Explicitly specifying the remote and branch will merge in that branch
    run dolt pull test-remote test-branch
    [ "$status" -eq 0 ]
    run dolt sql -q "show tables"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "t1" ]] || false

    # Make a conflicting working set change and test that pull complains
    dolt reset --hard HEAD^1
    dolt sql -q "create table t1 (pk int primary key);"
    run dolt pull test-remote test-branch
    [ "$status" -eq 1 ]
    [[ "$output" =~ 'local changes to the following tables would be overwritten by merge' ]] || false

    # Commit changes and test that a merge conflict fails the pull
    dolt add .
    dolt commit -am "adding new t1 table"
    run dolt pull test-remote test-branch
    [ "$status" -eq 1 ]
    [[ "$output" =~ "table with same name added in 2 commits can't be merged" ]] || false
}

@test "remotes: push and pull from non-main branch and use --set-upstream" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt checkout -b test-branch
    run dolt push --set-upstream test-remote test-branch
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "panic:" ]] || false
    dolt sql -q "create table test (pk int, c1 int, primary key(pk))"
    dolt add .
    dolt commit -m "Added test table"
    run dolt push
    [ "$status" -eq 0 ]
}

@test "remotes: push output" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt checkout -b test-branch
    dolt sql -q "create table test (pk int, c1 int, primary key(pk))"
    dolt add .
    dolt commit -m "Added test table"
    dolt push --set-upstream test-remote test-branch | tr "\n" "*" > output.txt
    run tail -c 1 output.txt
    [ "$output" = "*" ]
}

@test "remotes: push and pull with docs from remote" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    echo "license-text" > LICENSE.md
    dolt docs upload LICENSE.md LICENSE.md
    echo "readme-text" > README.md
    dolt docs upload README.md README.md
    dolt add .
    dolt commit -m "test doc commit"
    dolt push test-remote main
    cd "dolt-repo-clones"
    run dolt clone http://localhost:50051/test-org/test-repo
    [ "$status" -eq 0 ]

    cd test-repo
    run dolt log
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test doc commit" ]] || false

    cd ../../
    echo "updated-license" > LICENSE.md
    dolt docs upload LICENSE.md LICENSE.md
    dolt add .
    dolt commit -m "updated license"
    dolt push test-remote main

    cd dolt-repo-clones/test-repo
    run dolt pull
    [[ "$output" =~ "Updating" ]] || false
    run dolt log
    [ "$status" -eq 0 ]
    [[ "$output" =~ "updated license" ]] || false
    dolt docs print LICENSE.md > LICENSE.md
    run cat LICENSE.md
    [ "$status" -eq 0 ]
    [[ "$output" =~ "updated-license" ]] || false
}

@test "remotes: push and pull tags to/from remote" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt sql <<SQL
CREATE TABLE test (pk int PRIMARY KEY);
INSERT INTO  test VALUES (1),(2),(3);
SQL
    dolt add . && dolt commit -m "added table test"
    dolt push test-remote main
    cd "dolt-repo-clones"
    run dolt clone http://localhost:50051/test-org/test-repo
    [ "$status" -eq 0 ]

    cd ../
    dolt tag v1 head
    dolt push test-remote v1

    cd dolt-repo-clones/test-repo
    dolt pull
    [ "$status" -eq 0 ]
    run dolt tag
    [ "$status" -eq 0 ]
    [[ "$output" =~ "v1" ]] || false
}

@test "remotes: tags are fetched when pulling" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt sql <<SQL
CREATE TABLE test (pk int PRIMARY KEY);
INSERT INTO  test VALUES (1),(2),(3);
SQL
    dolt add . && dolt commit -m "added table test"
    dolt push test-remote main
    cd "dolt-repo-clones"
    run dolt clone http://localhost:50051/test-org/test-repo
    [ "$status" -eq 0 ]

     cd ../
    dolt tag v1 head -m "tag message"
    dolt push test-remote v1
    dolt checkout -b other
    dolt sql -q "INSERT INTO test VALUES (8),(9),(10)"
    dolt add . && dolt commit -m "added values on branch other"
    dolt push -u test-remote other
    dolt tag other_tag head  -m "other message"
    dolt push test-remote other_tag

    cd dolt-repo-clones/test-repo
    run dolt pull
    [ "$status" -eq 0 ]
    run dolt tag -v
    [ "$status" -eq 0 ]
    [[ "$output" =~ "v1" ]] || false
    [[ "$output" =~ "tag message" ]] || false
    [[ "$output" =~ "other_tag" ]] || false
    [[ "$output" =~ "other message" ]] || false
}

@test "remotes: clone a remote" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "test commit"
    dolt push test-remote main
    cd "dolt-repo-clones"
    run dolt clone http://localhost:50051/test-org/test-repo
    [ "$status" -eq 0 ]
    [[ "$output" =~ "cloning http://localhost:50051/test-org/test-repo" ]] || false
    cd test-repo
    run dolt log
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test commit" ]] || false
    run dolt status
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "LICENSE.md" ]] || false
    [[ ! "$output" =~ "README.md" ]] || false
    run ls
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "LICENSE.md" ]] || false
    [[ ! "$output" =~ "README.md" ]] || false
}

@test "remotes: read tables test" {
    # create table t1 and commit
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt sql <<SQL
CREATE TABLE t1 (
  pk BIGINT NOT NULL,
  PRIMARY KEY (pk)
);
SQL
    dolt add t1
    dolt commit -m "added t1"

    # create table t2 and commit
    dolt sql <<SQL
CREATE TABLE t2 (
  pk BIGINT NOT NULL,
  PRIMARY KEY (pk)
);
SQL
    dolt add t2
    dolt commit -m "added t2"

    # create table t3 and commit
    dolt sql <<SQL
CREATE TABLE t3 (
  pk BIGINT NOT NULL,
  PRIMARY KEY (pk)
);
SQL
    dolt add t3
    dolt commit -m "added t3"

    # push repo
    dolt push test-remote main
    cd "dolt-repo-clones"

    # Create a read latest tables and verify we have all the tables
    dolt read-tables http://localhost:50051/test-org/test-repo main
    cd test-repo
    run dolt ls
    [ "$status" -eq 0 ]
    [[ "$output" =~ "t1" ]] || false
    [[ "$output" =~ "t2" ]] || false
    [[ "$output" =~ "t3" ]] || false
    cd ..

    # Read specific table from latest with a specified directory
    dolt read-tables --dir clone_t1_t2 http://localhost:50051/test-org/test-repo main t1 t2
    cd clone_t1_t2
    run dolt ls
    [ "$status" -eq 0 ]
    [[ "$output" =~ "t1" ]] || false
    [[ "$output" =~ "t2" ]] || false
    [[ ! "$output" =~ "t3" ]] || false
    cd ..

    # Read tables from parent of parent of the tip of main. Should only have table t1
    dolt read-tables --dir clone_t1 http://localhost:50051/test-org/test-repo main~2
    cd clone_t1
    run dolt ls
    [ "$status" -eq 0 ]
    [[ "$output" =~ "t1" ]] || false
    [[ ! "$output" =~ "t2" ]] || false
    [[ ! "$output" =~ "t3" ]] || false
    cd ..
}

@test "remotes: clone a remote with docs" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    echo "license-text" > LICENSE.md
    dolt docs upload LICENSE.md LICENSE.md
    echo "readme-text" > README.md
    dolt docs upload README.md README.md
    dolt add .
    dolt commit -m "test doc commit"
    dolt push test-remote main
    cd "dolt-repo-clones"
    run dolt clone http://localhost:50051/test-org/test-repo
    [ "$status" -eq 0 ]
    [[ "$output" =~ "cloning http://localhost:50051/test-org/test-repo" ]] || false
    cd test-repo
    run dolt log
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test doc commit" ]] || false
    run dolt status
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "LICENSE.md" ]] || false
    [[ ! "$output" =~ "README.md" ]] || false
    dolt docs print LICENSE.md > LICENSE.md
    dolt docs print README.md > README.md
    run ls
    [ "$status" -eq 0 ]
    [[ "$output" =~ "LICENSE.md" ]] || false
    [[ "$output" =~ "README.md" ]] || false
    run cat LICENSE.md
    [ "$status" -eq 0 ]
    [[ "$output" =~ "license-text" ]] || false
    run cat README.md
    [ "$status" -eq 0 ]
    [[ "$output" =~ "readme-text" ]] || false
}

@test "remotes: clone an empty remote" {
    run dolt clone http://localhost:50051/test-org/empty
    [ "$status" -eq 1 ]
    [[ "$output" =~ "clone failed" ]] || false
    [[ "$output" =~ "remote at that url contains no Dolt data" ]] || false
}

@test "remotes: clone a non-existent remote" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    cd "dolt-repo-clones"
    run dolt clone http://localhost:50051/foo/bar
    [ "$status" -eq 1 ]
    [[ "$output" =~ "clone failed" ]] || false
    [[ "$output" =~ "remote at that url contains no Dolt data" ]] || false
}

@test "remotes: clone a different branch than main" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt checkout -b test-branch
    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "test commit"
    dolt push test-remote test-branch
    cd "dolt-repo-clones"
    run dolt clone -b test-branch http://localhost:50051/test-org/test-repo
    [ "$status" -eq 0 ]
    [[ "$output" =~ "cloning http://localhost:50051/test-org/test-repo" ]] || false
    cd test-repo
    run dolt branch
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "main" ]] || false
    [[ "$output" =~ "test-branch" ]] || false
    run dolt log
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test commit" ]] || false
}

@test "remotes: call a clone's remote something other than origin" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "test commit"
    dolt push test-remote main
    cd "dolt-repo-clones"
    run dolt clone --remote test-remote http://localhost:50051/test-org/test-repo
    [ "$status" -eq 0 ]
    [[ "$output" =~ "cloning http://localhost:50051/test-org/test-repo" ]] || false
    cd test-repo
    run dolt log
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test commit" ]] || false
    run dolt remote -v
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test-remote" ]] || false
    [[ ! "$output" =~ "origin" ]] || false
}

@test "remotes: dolt fetch" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt push test-remote main
    run dolt fetch test-remote
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    run dolt fetch test-remote refs/heads/main:refs/remotes/test-remote/main
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    run dolt fetch poop refs/heads/main:refs/remotes/poop/main
    [ "$status" -eq 1 ]
    [[ "$output" =~ "unknown remote" ]] || false
    run dolt fetch test-remote refs/heads/main:refs/remotes/test-remote/poop
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    run dolt branch -v -a
    [ "$status" -eq 0 ]
    [[ "$output" =~ "remotes/test-remote/poop" ]] || false
}

@test "remotes: fetch output" {
    # create main remote branch
    dolt remote add origin http://localhost:50051/test-org/test-repo
    dolt sql -q 'create table test (id int primary key);'
    dolt add .
    dolt commit -m 'create test table.'
    dolt push origin main:main

    # create remote branch "branch1"
    dolt checkout -b branch1
    dolt sql -q 'insert into test (id) values (1), (2), (3);'
    dolt add .
    dolt commit -m 'add some values to branch 1.'
    dolt push --set-upstream origin branch1

    # create remote branch "branch2"
    dolt checkout -b branch2
    dolt sql -q 'insert into test (id) values (4), (5), (6);'
    dolt add .
    dolt commit -m 'add some values to branch 2.'
    dolt push --set-upstream origin branch2

    # create first clone
    cd dolt-repo-clones
    dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
    dolt status
    run dolt status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "On branch main" ]] || false
    [[ "$output" =~ "nothing to commit, working tree clean" ]] || false

    cd ../..

    # create second clone
    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo test-repo2
    cd test-repo2
    dolt status
    run dolt status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "On branch main" ]] || false
    [[ "$output" =~ "nothing to commit, working tree clean" ]] || false

    # CHANGE 1: add more data to branch1
    dolt checkout -b branch1 remotes/origin/branch1
    dolt sql -q 'insert into test (id) values (100), (101), (102);'
    dolt add .
    dolt commit -m 'add more values to branch 1.'
    dolt push --set-upstream origin branch1

    # CHANGE 2: add more data to branch2
    dolt checkout -b branch2 remotes/origin/branch2
    dolt sql -q 'insert into test (id) values (103), (104), (105);'
    dolt add .
    dolt commit -m 'add more values to branch 2.'
    dolt push --set-upstream origin branch2

    # CHANGE 3: create remote branch "branch3"
    dolt checkout -b branch3
    dolt sql -q 'insert into test (id) values (7), (8), (9);'
    dolt add .
    dolt commit -m 'add some values to branch 3.'
    dolt push --set-upstream origin branch3

    # CHANGE 4: create remote branch "branch4"
    dolt checkout -b branch4
    dolt sql -q 'insert into test (id) values (10), (11), (12);'
    dolt add .
    dolt commit -m 'add some values to  branch 4.'
    dolt push --set-upstream origin branch4

    cd ..
    cd test-repo
    run dolt fetch
    [ "$status" -eq 0 ]
    # The number of $lines and $output printed is non-deterministic
    # due to EphemeralPrinter. We can't test for their length here.
    [ "$output" != "" ]

    run dolt fetch
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "remotes: dolt fetch with docs" {
    # Initial commit of docs on remote
    echo "initial-license" > LICENSE.md
    dolt docs upload LICENSE.md LICENSE.md
    echo "initial-readme" > README.md
    dolt docs upload README.md README.md
    dolt add .
    dolt commit -m "initial doc commit"
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt push test-remote main
    run dolt fetch test-remote
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    run cat README.md
    [ "$status" -eq 0 ]
    [[ "$output" =~ "initial-readme" ]] || false
    run cat LICENSE.md
    [ "$status" -eq 0 ]
    [[ "$output" =~ "initial-license" ]] || false

    # Clone the initial docs/repo into dolt-repo-clones/test-repo
    cd "dolt-repo-clones"
    run dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
    dolt docs print LICENSE.md > LICENSE.md
    dolt docs print README.md > README.md
    run cat LICENSE.md
    [ "$status" -eq 0 ]
    [[ "$output" =~ "initial-license" ]] || false
    run cat README.md
    [ "$status" -eq 0 ]
    [[ "$output" =~ "initial-readme" ]] || false
    # Change the docs
    echo "dolt-repo-clones-license" > LICENSE.md
    dolt docs upload LICENSE.md LICENSE.md
    echo "dolt-repo-clones-readme" > README.md
    dolt docs upload README.md README.md
    dolt add .
    dolt commit -m "dolt-repo-clones updated docs"

    # Go back to original repo, and change the docs again
    cd ../../
    echo "initial-license-updated" > LICENSE.md
    dolt docs upload LICENSE.md LICENSE.md
    echo "initial-readme-updated" > README.md
    dolt docs upload README.md README.md
    dolt add .
    dolt commit -m "update initial doc values in test-org/test-repo"

    # Go back to dolt-repo-clones/test-repo and fetch the test-remote
    cd dolt-repo-clones/test-repo
    run dolt fetch test-remote
    run cat LICENSE.md
    [ "$status" -eq 0 ]
    [[ "$output" =~ "dolt-repo-clones-license" ]] || false
    run cat README.md
    [ "$status" -eq 0 ]
    [[ "$output" =~ "dolt-repo-clones-readme" ]] || false
}

@test "remotes: dolt merge with origin/main syntax." {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt push test-remote main
    dolt fetch test-remote
    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo
    cd ..
    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "test commit"
    dolt push test-remote main
    cd "dolt-repo-clones/test-repo"
    run dolt log
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "test commit" ]] || false
    run dolt merge origin/main
    [ "$status" -eq 0 ]
    [[ "$output" =~ "up-to-date" ]]
    run dolt fetch
    [ "$status" -eq 0 ]
    run dolt merge origin/main
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Fast-forward" ]]
    run dolt log
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test commit" ]] || false
}

@test "remotes: dolt fetch and merge with remotes/origin/main syntax" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt push test-remote main
    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo
    cd ..
    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "test commit"
    dolt push test-remote main
    cd "dolt-repo-clones/test-repo"
    run dolt merge remotes/origin/main
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Everything up-to-date" ]]
    run dolt fetch origin main
    [ "$status" -eq 0 ]
    run dolt merge remotes/origin/main
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Fast-forward" ]]
}

@test "remotes: try to push a remote that is behind tip" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt push test-remote main
    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo
    cd ..
    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "test commit"
    dolt push test-remote main
    cd "dolt-repo-clones/test-repo"
    run dolt push origin main
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Everything up-to-date" ]] || false
    dolt fetch
    run dolt push origin main
    [ "$status" -eq 1 ]
    [[ "$output" =~ "tip of your current branch is behind" ]] || false
}

@test "remotes: generate a merge with no conflict with a remote branch" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt push test-remote main
    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo
    cd ..
    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "test commit"
    dolt push test-remote main
    cd "dolt-repo-clones/test-repo"
    dolt sql <<SQL
CREATE TABLE test2 (
  pk BIGINT NOT NULL COMMENT 'tag:10',
  c1 BIGINT COMMENT 'tag:11',
  c2 BIGINT COMMENT 'tag:12',
  c3 BIGINT COMMENT 'tag:13',
  c4 BIGINT COMMENT 'tag:14',
  c5 BIGINT COMMENT 'tag:15',
  PRIMARY KEY (pk)
);
SQL
    dolt add test2
    dolt commit -m "another test commit"
    run dolt pull origin --no-edit
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Updating" ]] || false

    run dolt log --oneline -n 1
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Merge branch 'main' of" ]] || false
    [[ ! "$output" =~ "test commit" ]] || false
    [[ ! "$output" =~ "another test commit" ]] || false
}

@test "remotes: generate a merge with a conflict with a remote branch" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "created table"
    dolt push --set-upstream test-remote main
    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo
    cd ..
    dolt sql -q "insert into test values (0, 0, 0, 0, 0, 0)"
    dolt add test
    dolt commit -m "row to generate conflict"
    dolt push test-remote main
    cd "dolt-repo-clones/test-repo"
    dolt sql -q "insert into test values (0, 1, 1, 1, 1, 1)"
    dolt add test
    dolt commit -m "conflicting row"
    run dolt pull origin
    [ "$status" -eq 0 ]
    [[ "$output" =~ "CONFLICT" ]]
    dolt conflicts resolve test --ours
    dolt add test
    dolt commit -m "Fixed conflicts"
    run dolt push origin main
    cd ../../
    dolt pull test-remote
    run dolt log
    [[ "$output" =~ "Fixed conflicts" ]] || false
}

@test "remotes: clone sets your current branch appropriately" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "test commit"
    dolt checkout -b aaa
    dolt checkout -b zzz
    dolt push test-remote aaa
    dolt push test-remote zzz
    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
    dolt branch

    # main hasn't been pushed so expect aaa to be the current branch and the string main should not be present
    # branches should be sorted lexicographically
    run dolt branch
    [ "$status" -eq 0 ]
    [[ "$output" =~ "* aaa" ]] || false
    [[ ! "$output" =~ "main" ]] || false
    cd ../..
    dolt push test-remote main
    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo test-repo2
    cd test-repo2

    # main pushed so it should be the current branch.
    run dolt branch
    [ "$status" -eq 0 ]
    [[ "$output" =~ "* main" ]] || false
}

@test "remotes: dolt pull onto a dirty working set fails" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "created table"
    dolt push test-remote main
    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo
    cd ..
    dolt sql -q "insert into test values (0, 0, 0, 0, 0, 0)"
    dolt add test
    dolt commit -m "row to generate conflict"
    dolt push test-remote main
    cd "dolt-repo-clones/test-repo"
    dolt sql -q "insert into test values (0, 1, 1, 1, 1, 1)"
    run dolt pull origin
    [ "$status" -ne 0 ]
    [[ "$output" =~ "error: Your local changes to the following tables would be overwritten by merge:" ]] || false
    [[ "$output" =~ "test" ]] || false
    [[ "$output" =~ "Please commit your changes before you merge." ]] || false
}

@test "remotes: force push to main" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt push test-remote main

    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo
    cd ..

    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "test commit"
    dolt push test-remote main
    cd "dolt-repo-clones/test-repo"
    dolt sql <<SQL
CREATE TABLE other (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add other
    dolt commit -m "added other table"
    dolt fetch
    run dolt push origin main
    [ "$status" -eq 1 ]
    [[ "$output" =~ "tip of your current branch is behind" ]] || false
    dolt push -f main
    run dolt push -f origin main
    [ "$status" -eq 0 ]
}

@test "remotes: force fetch from main" {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt push --set-upstream test-remote main

    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo
    cd ..

    dolt sql <<SQL
CREATE TABLE test (
  pk BIGINT NOT NULL COMMENT 'tag:0',
  c1 BIGINT COMMENT 'tag:1',
  c2 BIGINT COMMENT 'tag:2',
  c3 BIGINT COMMENT 'tag:3',
  c4 BIGINT COMMENT 'tag:4',
  c5 BIGINT COMMENT 'tag:5',
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "test commit"
    dolt push test-remote main
    cd "dolt-repo-clones/test-repo"
    dolt sql <<SQL
CREATE TABLE other (
  pk BIGINT NOT NULL COMMENT 'tag:10',
  c1 BIGINT COMMENT 'tag:11',
  c2 BIGINT COMMENT 'tag:12',
  c3 BIGINT COMMENT 'tag:13',
  c4 BIGINT COMMENT 'tag:14',
  c5 BIGINT COMMENT 'tag:15',
  PRIMARY KEY (pk)
);
SQL
    dolt add other
    dolt commit -m "added other table"
    dolt fetch
    dolt push -f origin main
    cd ../../
    run dolt fetch test-remote
    [ "$status" -ne 0 ]
    run dolt pull
    [ "$status" -ne 0 ]
    run dolt fetch -f test-remote
    [ "$status" -eq 0 ]
    run dolt pull --no-edit
    [ "$status" -eq 0 ]
}

@test "remotes: validate that a config isn't needed for a pull." {
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt push test-remote main
    dolt fetch test-remote
    cd "dolt-repo-clones"
    dolt clone http://localhost:50051/test-org/test-repo
    cd ..
    dolt sql <<SQL
CREATE TABLE test (
  pk int,
  val int,
  PRIMARY KEY (pk)
);
SQL
    dolt add test
    dolt commit -m "test commit"
    dolt push test-remote main

    # cd to the other directory and execute a pull without a config
    cd "dolt-repo-clones/test-repo"
    dolt config --global --unset user.name
    dolt config --global --unset user.email

    run dolt pull
    [ "$status" -eq 0 ]
    run dolt log
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test commit" ]] || false

    # turn back on the configs and make a change in the remote
    dolt config --global --add user.name mysql-test-runner
    dolt config --global --add user.email mysql-test-runner@liquidata.co

    cd ../../
    dolt sql -q "insert into test values (1,1)"
    dolt commit -am "commit from main repo"
    dolt push test-remote main

    # Try a --no-ff merge and make sure it fails
    cd "dolt-repo-clones/test-repo"
    # turn configs off again
    dolt config --global --unset user.name
    dolt config --global --unset user.email

    run dolt pull --no-ff
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Aborting commit due to empty committer name. Is your config set?" ]] || false

    # Now do a two sided merge
    dolt config --global --add user.name mysql-test-runner
    dolt config --global --add user.email mysql-test-runner@liquidata.co

    dolt sql -q "insert into test values (2,1)"
    dolt commit -am "commit from test repo"

    cd ../../
    dolt sql -q "insert into test values (2,2)"
    dolt commit -am "commit from main repo"
    dolt push test-remote main

    cd "dolt-repo-clones/test-repo"
    dolt config --global --unset user.name
    dolt config --global --unset user.email

    run dolt pull
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Aborting commit due to empty committer name. Is your config set?" ]] || false
}

create_main_remote_branch() {
    dolt remote add origin http://localhost:50051/test-org/test-repo
    dolt sql -q 'create table test (id int primary key);'
    dolt add .
    dolt commit -m 'create test table.'
    dolt push origin main:main
}

create_two_more_remote_branches() {
    dolt commit --allow-empty -m 'another commit.'
    dolt push origin main:branch-one
    dolt sql -q 'insert into test (id) values (1), (2), (3);'
    dolt add .
    dolt commit -m 'add some values.'
    dolt push origin main:branch-two
}

create_three_remote_branches() {
    create_main_remote_branch
    create_two_more_remote_branches
}

create_remote_branch() {
    local b="$1"
    dolt push origin main:"$b"
}

create_five_remote_branches_main_only() {
  dolt remote add origin http://localhost:50051/test-org/test-repo
  create_remote_branch "zzz"
  create_remote_branch "dev"
  create_remote_branch "prod"
  create_remote_branch "main"
  create_remote_branch "aaa"
}

create_five_remote_branches_master_only() {
  dolt remote add origin http://localhost:50051/test-org/test-repo
  create_remote_branch "111"
  create_remote_branch "dev"
  create_remote_branch "master"
  create_remote_branch "prod"
  create_remote_branch "aaa"
}

create_five_remote_branches_no_main_no_master() {
  dolt remote add origin http://localhost:50051/test-org/test-repo
  create_remote_branch "123"
  create_remote_branch "dev"
  create_remote_branch "456"
  create_remote_branch "prod"
  create_remote_branch "aaa"
}

create_five_remote_branches_main_and_master() {
  dolt remote add origin http://localhost:50051/test-org/test-repo
  create_remote_branch "master"
  create_remote_branch "dev"
  create_remote_branch "456"
  create_remote_branch "main"
  create_remote_branch "aaa"
}

@test "remotes: clone checks out main, if found" {
    create_five_remote_branches_main_only
    cd dolt-repo-clones
    dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
    dolt status
    run dolt status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "On branch main" ]] || false
    [[ "$output" =~ "nothing to commit, working tree clean" ]] || false
}

@test "remotes: clone checks out master, if main not found" {
    create_five_remote_branches_master_only
    cd dolt-repo-clones
    dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
    dolt status
    run dolt status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "On branch master" ]] || false
    [[ "$output" =~ "nothing to commit, working tree clean" ]] || false
}

@test "remotes: clone checks out main, if both main and master found" {
    create_five_remote_branches_main_and_master
    cd dolt-repo-clones
    dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
    dolt status
    run dolt status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "On branch main" ]] || false
    [[ "$output" =~ "nothing to commit, working tree clean" ]] || false
}

@test "remotes: clone checks out first lexicographical branch if neither main nor master found" {
    create_five_remote_branches_no_main_no_master
    cd dolt-repo-clones
    dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
    dolt status
    run dolt status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "On branch 123" ]] || false
    [[ "$output" =~ "nothing to commit, working tree clean" ]] || false
}

@test "remotes: clone creates remotes refs for all remote branches" {
    create_three_remote_branches
    cd dolt-repo-clones
    dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
    run dolt branch -a
    [ "$status" -eq 0 ]
    [[ "$output" =~ "* main" ]] || false
    [[ ! "$output" =~ " branch-one" ]] || false
    [[ ! "$output" =~ " branch-two" ]] || false
    [[ "$output" =~ "remotes/origin/main" ]] || false
    [[ "$output" =~ "remotes/origin/branch-one" ]] || false
    [[ "$output" =~ "remotes/origin/branch-two" ]] || false
}

@test "remotes: fetch creates new remote refs for new remote branches" {
    create_main_remote_branch

    cd dolt-repo-clones
    dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
    dolt branch -a
    run dolt branch -a
    [ "$status" -eq 0 ]
    [[ "$output" =~ "* main" ]] || false
    [[ "$output" =~ "remotes/origin/main" ]] || false

    cd ../../
    create_two_more_remote_branches

    cd dolt-repo-clones/test-repo
    dolt fetch
    run dolt branch -a
    [ "$status" -eq 0 ]
    [[ "$output" =~ "* main" ]] || false
    [[ "$output" =~ "remotes/origin/main" ]] || false
    [[ "$output" =~ "remotes/origin/branch-one" ]] || false
    [[ "$output" =~ "remotes/origin/branch-two" ]] || false
}

setup_ref_test() {
    create_main_remote_branch

    cd dolt-repo-clones
    dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
}

@test "remotes: can use refs/remotes/origin/... as commit reference for log" {
    setup_ref_test
    dolt log refs/remotes/origin/main
}

@test "remotes: can use refs/remotes/origin/... as commit reference for diff" {
    setup_ref_test
    dolt diff HEAD refs/remotes/origin/main
    dolt diff refs/remotes/origin/main HEAD
}

@test "remotes: can use refs/remotes/origin/... as commit reference for merge" {
    setup_ref_test
    dolt merge refs/remotes/origin/main -m "merge"
}

@test "remotes: can use remotes/origin/... as commit reference for log" {
    setup_ref_test
    dolt log remotes/origin/main
}

@test "remotes: can use remotes/origin/... as commit reference for diff" {
    setup_ref_test
    dolt diff HEAD remotes/origin/main
    dolt diff remotes/origin/main HEAD
}

@test "remotes: can use remotes/origin/... as commit reference for merge" {
    setup_ref_test
    dolt merge remotes/origin/main -m "merge"
}

@test "remotes: can use origin/... as commit reference for log" {
    setup_ref_test
    dolt log origin/main
}

@test "remotes: can use origin/... as commit reference for diff" {
    setup_ref_test
    dolt diff HEAD origin/main
    dolt diff origin/main HEAD
}

@test "remotes: can use origin/... as commit reference for merge" {
    setup_ref_test
    dolt merge origin/main -m "merge"
}

@test "remotes: can delete remote reference branch as origin/..." {
    setup_ref_test
    cd ../../
    create_two_more_remote_branches
    cd dolt-repo-clones/test-repo
    dolt fetch # TODO: Remove this fetch once clone works

    dolt branch -r -d origin/main
    run dolt branch -a
    [ "$status" -eq 0 ]
    [[ "$output" =~ "* main" ]] || false
    [[ ! "$output" =~ "remotes/origin/main" ]] || false
    [[ "$output" =~ "remotes/origin/branch-one" ]] || false
    [[ "$output" =~ "remotes/origin/branch-two" ]] || false
    dolt branch -r -d origin/branch-one origin/branch-two
    run dolt branch -a
    [ "$status" -eq 0 ]
    [[ "$output" =~ "* main" ]] || false
    [[ ! "$output" =~ "remotes/origin/main" ]] || false
    [[ ! "$output" =~ "remotes/origin/branch-one" ]] || false
    [[ ! "$output" =~ "remotes/origin/branch-two" ]] || false
}

@test "remotes: can list remote reference branches with -r" {
    setup_ref_test
    cd ../../
    create_two_more_remote_branches
    cd dolt-repo-clones/test-repo
    dolt fetch # TODO: Remove this fetch once clone works

    run dolt branch -r
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "* main" ]] || false
    [[ "$output" =~ "remotes/origin/main" ]] || false
    [[ "$output" =~ "remotes/origin/branch-one" ]] || false
    [[ "$output" =~ "remotes/origin/branch-two" ]] || false
    run dolt branch
    [ "$status" -eq 0 ]
    [[ "$output" =~ "* main" ]] || false
    [[ ! "$output" =~ "remotes/origin/main" ]] || false
    [[ ! "$output" =~ "remotes/origin/branch-one" ]] || false
    [[ ! "$output" =~ "remotes/origin/branch-two" ]] || false
    run dolt branch -a
    [ "$status" -eq 0 ]
    [[ "$output" =~ "* main" ]] || false
    [[ "$output" =~ "remotes/origin/main" ]] || false
    [[ "$output" =~ "remotes/origin/branch-one" ]] || false
    [[ "$output" =~ "remotes/origin/branch-two" ]] || false
}

@test "remotes: not specifying a branch throws an error" {
    run dolt push -u origin
    [ "$status" -eq 1 ]
    [[ "$output" =~ "error: --set-upstream requires <remote> and <refspec> params." ]] || false
}

@test "remotes: pushing empty branch does not panic" {
    run dolt push origin ''
    [ "$status" -eq 1 ]
    [[ "$output" =~ "invalid ref spec: ''" ]] || false
}

@test "remotes: existing parent directory is not wiped when clone fails" {
    # Create the new testdir and save it
    mkdir testdir && cd testdir
    run pwd
    testdir=$output

    # Create a clone operation that purposely fails on a valid remote
    mkdir clone_root
    mkdir dest && cd dest

    run dolt clone "file://../clone_root" .
    [ "$status" -eq 1 ]
    [[ "$output" =~ "clone failed" ]] || false

    # Validates that the directory exists
    run ls $testdir
    [ "$status" -eq 0 ]
    [[ "$output" =~ "clone_root" ]] || false
    [[ "$output" =~ "dest" ]] || false

    # Check that .dolt was deleted
    run ls -a $testdir/dest
    ! [[ "$output" =~ ".dolt" ]] || false

    # try again and now make sure that /dest/.dolt is correctly deleted instead of dest/
    cd ..
    run dolt clone "file://./clone_root" dest/
    [ "$status" -eq 1 ]
    [[ "$output" =~ "clone failed" ]] || false

    run ls $testdir
    [ "$status" -eq 0 ]
    [[ "$output" =~ "clone_root" ]] || false
    [[ "$output" =~ "dest" ]] || false

    run ls -a $testdir/dest
    ! [[ "$output" =~ ".dolt" ]] || false
}

@test "remotes: fetching unknown remotes should error" {
    setup_ref_test
    cd ../../
    cd dolt-repo-clones/test-repo
    run dolt fetch remotes/dasdas
    [ "$status" -eq 1 ]
    [[ ! "$output" =~ "panic" ]] || false
    [[ "$output" =~ "'remotes/dasdas' does not appear to be a dolt database" ]] || false
}

@test "remotes: fetching added invalid remote correctly errors" {
    setup_ref_test
    cd ../../
    cd dolt-repo-clones/test-repo
    dolt remote add myremote dolthub/fake

    run dolt fetch myremote
    [ "$status" -eq 1 ]
    [[ ! "$output" =~ "panic" ]] || false
    [[ "$output" =~ "permission denied" ]] || false
}

@test "remotes: fetching unknown remote ref errors accordingly" {
   setup_ref_test
   cd ../../
   cd dolt-repo-clones/test-repo

   run dolt fetch origin dadasdfasdfa
   [ "$status" -eq 1 ]
   [[ "$output" =~ "invalid ref spec: 'dadasdfasdfa'" ]] || false
}

@test "remotes: checkout with -f flag without conflict" {
    # create main remote branch
    dolt remote add origin http://localhost:50051/test-org/test-repo
    dolt sql -q 'create table test (id int primary key);'
    dolt sql -q 'insert into test (id) values (8);'
    dolt add .
    dolt commit -m 'create test table.'
    dolt push origin main:main

    # create remote branch "branch1"
    dolt checkout -b branch1
    dolt sql -q 'insert into test (id) values (1), (2), (3);'
    dolt add .
    dolt commit -m 'add some values to branch 1.'
    dolt push --set-upstream origin branch1

    run dolt checkout -f main
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Switched to branch 'main'" ]] || false

    run dolt sql -q "select * from test;"
    [[ "$output" =~ "8" ]] || false
    [[ ! "$output" =~ "1" ]] || false
    [[ ! "$output" =~ "2" ]] || false
    [[ ! "$output" =~ "3" ]] || false

    dolt checkout branch1
    run dolt sql -q "select * from test;"
    [[ "$output" =~ "1" ]] || false
    [[ "$output" =~ "2" ]] || false
    [[ "$output" =~ "3" ]] || false
    [[ "$output" =~ "8" ]] || false
}

@test "remotes: checkout with -f flag with conflict" {
    # create main remote branch
    dolt remote add origin http://localhost:50051/test-org/test-repo
    dolt sql -q 'create table test (id int primary key);'
    dolt sql -q 'insert into test (id) values (8);'
    dolt add .
    dolt commit -m 'create test table.'
    dolt push origin main:main

    # create remote branch "branch1"
    dolt checkout -b branch1
    dolt sql -q 'insert into test (id) values (1), (2), (3);'
    dolt add .
    dolt commit -m 'add some values to branch 1.'
    dolt push --set-upstream origin branch1

    dolt sql -q 'insert into test (id) values (4);'
    run dolt checkout main
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Please commit your changes or stash them before you switch branches." ]] || false

    run dolt checkout -f main
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Switched to branch 'main'" ]] || false

    run dolt sql -q "select * from test;"
    [[ "$output" =~ "8" ]] || false
    [[ ! "$output" =~ "4" ]] || false

    dolt checkout branch1
    run dolt sql -q "select * from test;"
    [[ "$output" =~ "1" ]] || false
    [[ "$output" =~ "2" ]] || false
    [[ "$output" =~ "3" ]] || false
    [[ "$output" =~ "8" ]] || false
    [[ ! "$output" =~ "4" ]] || false
}

@test "remotes: clone sets default upstream for main" {
    dolt remote add origin http://localhost:50051/test-org/test-repo
    dolt push origin main
    cd dolt-repo-clones
    dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
    dolt push
}

@test "remotes: set upstream succeeds even if up to date" {
    dolt remote add origin http://localhost:50051/test-org/test-repo
    dolt push origin main
    dolt checkout -b feature
    dolt push --set-upstream origin feature

    cd dolt-repo-clones
    dolt clone http://localhost:50051/test-org/test-repo
    cd test-repo
    dolt checkout -b feature
    run dolt push
    [ "$status" -eq 1 ]
    dolt push --set-upstream origin feature
    dolt push
}

@test "remotes: clone local repo with file url" {
    mkdir repo1
    cd repo1
    dolt init
    dolt commit --allow-empty -am "commit from repo1"

    cd ..
    dolt clone file://./repo1/.dolt/noms repo2
    cd repo2
    run dolt log
    [[ "$output" =~ "commit from repo1" ]] || false

    run dolt status
    [[ "$output" =~ "nothing to commit, working tree clean" ]] || false

    dolt commit --allow-empty -am "commit from repo2"
    dolt push

    cd ../repo1
    run dolt log
    [[ "$output" =~ "commit from repo1" ]]
    [[ "$output" =~ "commit from repo2" ]]
}

@test "remotes: clone local repo with absolute file path" {
    skiponwindows "absolute paths don't work on windows"
    mkdir repo1
    cd repo1
    dolt init
    dolt commit --allow-empty -am "commit from repo1"

    cd ..
    dolt clone file://$(pwd)/repo1/.dolt/noms repo2
    cd repo2
    run dolt log
    [[ "$output" =~ "commit from repo1" ]] || false

    run dolt status
    [[ "$output" =~ "nothing to commit, working tree clean" ]] || false

    dolt commit --allow-empty -am "commit from repo2"
    dolt push

    cd ../repo1
    run dolt log
    [[ "$output" =~ "commit from repo1" ]]
    [[ "$output" =~ "commit from repo2" ]]
}

@test "remotes: local clone does not contain working set changes" {
    mkdir repo1
    cd repo1
    dolt init
    run dolt sql -q "create table t (i int)"
    [ "$status" -eq 0 ]
    run dolt status
    [[ "$output" =~ "new table:" ]] || false

    cd ..
    dolt clone file://./repo1/.dolt/noms repo2
    cd repo2

    run dolt status
    [[ "$output" =~ "nothing to commit, working tree clean" ]] || false
}

@test "remotes: local clone pushes to other branch" {
    mkdir repo1
    cd repo1
    dolt init

    cd ..
    dolt clone file://./repo1/.dolt/noms repo2
    cd repo2
    dolt checkout -b other
    dolt sql -q "create table t (i int)"
    dolt add .
    dolt commit -am "adding table from other"
    dolt push origin other

    cd ../repo1
    dolt checkout other
    run dolt log
    [[ "$output" =~ "adding table from other" ]]
}

@test "remotes: dolt_remote uses the right db directory in a multidb env" {
    tempDir=$(mktemp -d)

    cd $tempDir
    mkdir db1
    cd db1
    dolt init
    cd ..

    run dolt sql -q "use db1; call dolt_remote('add', 'test1', 'foo/bar');"
    [ "$status" -eq 0 ]

    run grep "test1" db1/.dolt/repo_state.json
    [ "$status" -eq 0 ]
    [[ "$output" =~ '"name": "test1"' ]] || false
    [ ! -d ".dolt" ]

    run dolt sql -q "use db1; call dolt_remote('remove', 'test1');"
    [ "$status" -eq 0 ]
    [ ! -d ".dolt" ]
}

@test "remotes: dolt_remote add and remove works with other commands" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    run dolt sql <<SQL
CALL dolt_remote('add', 'origin', 'http://localhost:50051/test-org/test-repo');
CALL dolt_push('origin', 'main');
SQL
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "must provide a GRPCDialProvider param through GRPCDialProviderParam" ]] || false

    cd ..
    dolt clone http://localhost:50051/test-org/test-repo repo2

    cd repo2
    run dolt branch -va
    [[ "$output" =~ "main" ]] || false
    [[ ! "$output" =~ "other" ]] || false

    cd ../repo1
    dolt checkout -b other
    dolt push origin other

    cd ../repo2
    dolt pull
    run dolt branch -va
    [[ "$output" =~ "main" ]] || false
    [[ "$output" =~ "other" ]] || false

    dolt checkout main
    dolt sql -q "CREATE TABLE a(pk int primary key)"
    dolt add .
    dolt commit -am "add table a"
    dolt push

    cd ../repo1
    dolt sql -q "CALL dolt_remote('remove', 'origin')"
    run dolt pull
    [ "$status" -eq 1 ]
    [[ "$output" =~ "no remote" ]] || false
}

@test "remotes: dolt status on local repo compares with remote tracking" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add origin file://../remote
    dolt push --set-upstream origin main

    cd ..
    dolt clone file://./remote repo2

    cd repo2
    dolt sql -q "CREATE TABLE test (id int primary key)"
    dolt add .
    dolt commit -am "create table"
    run dolt push
    [ "$status" -eq "0" ]
    dolt log

    cd ../repo1
    run dolt status
    [[ "$output" =~ "nothing to commit, working tree clean" ]] || false

    dolt fetch
    run dolt status
    [[ "$output" =~ "behind" ]] || false
    [[ "$output" =~ "1 commit" ]] || false

    dolt sql -q "CREATE TABLE different (id int primary key)"
    dolt add .
    dolt commit -am "create different table"

    run dolt status
    [[ "$output" =~ "diverged" ]] || false
    [[ "$output" =~ "1 and 1" ]] || false

    dolt pull --no-edit
    run dolt status
    [[ "$output" =~ "ahead" ]] || false
    [[ "$output" =~ "2 commit" ]] || false
}

@test "remotes: dolt checkout --track origin/feature checks out new local branch 'feature' with upstream set" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add origin file://../remote
    dolt push --set-upstream origin main
    dolt checkout -b feature
    dolt push --set-upstream origin feature

    cd ..
    dolt clone file://./remote repo2

    cd repo2
    run dolt branch
    [[ ! "$output" =~ "feature" ]] || false

    run dolt checkout --track origin/feature
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Switched to branch 'feature'" ]] || false
    [[ "$output" =~ "branch 'feature' set up to track 'origin/feature'." ]] || false

    run dolt pull
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Everything up-to-date." ]] || false
}

@test "remotes: dolt checkout -b newbranch --track origin/feature checks out new local branch 'newbranch' with upstream set" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add origin file://../remote
    dolt push --set-upstream origin main
    dolt checkout -b feature
    dolt push --set-upstream origin feature

    cd ..
    dolt clone file://./remote repo2

    cd repo2
    run dolt branch
    [[ ! "$output" =~ "feature" ]] || false

    run dolt checkout -b newbranch --track origin/feature
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Switched to branch 'newbranch'" ]] || false
    [[ "$output" =~ "branch 'newbranch' set up to track 'origin/feature'." ]] || false

    run dolt pull
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Everything up-to-date." ]] || false

    dolt checkout main
    dolt branch -D newbranch

    # branch.autosetupmerge configuration defaults to --track, so the upstream is set
    run dolt checkout -b newbranch origin/feature
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Switched to branch 'newbranch'" ]] || false
    [[ "$output" =~ "branch 'newbranch' set up to track 'origin/feature'." ]] || false

    run dolt pull
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Everything up-to-date." ]] || false
}

@test "remotes: dolt branch track flag sets upstream" {
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add origin file://../remote
    dolt sql -q "CREATE TABLE a (pk int)"
    dolt add .
    dolt commit -am "add table a"
    dolt push --set-upstream origin main
    dolt checkout -b other
    dolt push --set-upstream origin other

    cd ..
    dolt clone file://./remote repo2

    cd repo2
    dolt branch
    [[ ! "$output" =~ "other" ]] || false

    run dolt branch --track other origin/other
    [ "$status" -eq 0 ]
    [[ "$output" =~ "branch 'other' set up to track 'origin/other'" ]] || false

    run dolt status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "On branch main" ]] || false

    dolt checkout other
    run dolt pull
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Everything up-to-date." ]] || false

    run dolt branch --track direct feature origin/other
    [ "$status" -eq 0 ]
    [[ "$output" =~ "branch 'feature' set up to track 'origin/other'" ]] || false

    run dolt status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "On branch other" ]] || false

    dolt commit --allow-empty -m "new commit to other"
    dolt push
    dolt checkout feature
    run dolt pull
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Fast-forward" ]] || false
}

@test "remotes: dolt_clone failure cleanup" {
    repoDir="$BATS_TMPDIR/dolt-repo-$$"

    # try to clone a remote that doesn't exist
    cd $repoDir
    run dolt sql -q 'call dolt_clone("file:///tmp/sanity/remote");'
    [ "$status" -eq 1 ]

    # Make sure there's nothing remaining from the failed clone
    [ ! -d "$repoDir/remote" ]
}

@test "remotes: dolt_clone procedure" {
    repoDir="$BATS_TMPDIR/dolt-repo-$$"

    # make directories outside of the dolt repo
    tempDir=$(mktemp -d)
    cd $tempDir
    mkdir remote
    mkdir repo1

    cd repo1
    dolt init
    dolt remote add origin file://../remote
    dolt push origin main
    dolt checkout -b other
    dolt push --set-upstream origin other

    cd $repoDir

    run dolt sql -q "call dolt_clone()"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "error: invalid number of arguments" ]] || false

    run dolt sql -q "call dolt_clone('file://$tempDir/remote', 'foo', 'bar')"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "error: invalid number of arguments" ]] || false

    # Clone a local database and check for all the branches
    run dolt sql -q "call dolt_clone('file://$tempDir/remote');"
    [ "$status" -eq 0 ]
    cd remote
    run dolt branch
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "other" ]] || false
    [[ "$output" =~ "main" ]] || false
    run dolt branch --remote
    [[ "$output" =~ "origin/other" ]] || false
    [[ "$output" =~ "origin/main" ]] || false
    cd ..

    # Ensure we can't clone it again
    run dolt sql -q "call dolt_clone('file://$tempDir/remote');"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "can't create database remote; database exists" ]] || false
    run dolt sql -q "show databases"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "remote" ]] || false

    # Drop the new database and re-clone it with a different name
    dolt sql -q "drop database remote"
    run dolt sql -q "show databases"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "repo2" ]] || false
    dolt sql -q "call dolt_clone('file://$tempDir/remote', 'repo2');"

    # Sanity check that we can use the new database
    dolt sql << SQL
use repo2;
create table new_table(a int primary key);
insert into new_table values (1), (2);
SQL
    cd repo2
    dolt add .
    dolt commit -am "a commit for main from repo2"
    dolt push origin main
    cd ..

    # Test -remote option to customize the origin remote name for the cloned DB
    run dolt sql -q "call dolt_clone('-remote', 'custom', 'file://$tempDir/remote', 'custom_remote');"
    [ "$status" -eq 0 ]
    run dolt sql -q "use custom_remote; select name from dolt_remotes;"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "custom" ]] || false

    # Test -branch option to only clone a single branch
    run dolt sql -q "call dolt_clone('-branch', 'other', 'file://$tempDir/remote', 'single_branch');"
    [ "$status" -eq 0 ]
    run dolt sql -q "use single_branch; select name from dolt_branches;"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "other" ]] || false
    [[ ! "$output" =~ "main" ]] || false
    run dolt sql -q "use single_branch; select active_branch();"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "other" ]] || false
    # TODO: To match Git's semantics, clone for a single branch should NOT create any other
    #       remote tracking branches (https://github.com/dolthub/dolt/issues/3873)
    # run dolt checkout main
    # [ "$status" -eq 1 ]

    # Set up a test repo in the remote server
    cd repo2
    dolt remote add test-remote http://localhost:50051/test-org/test-repo
    dolt sql -q "CREATE TABLE test_table (pk INT)"
    dolt add .
    dolt commit -am "main commit"
    dolt push test-remote main
    cd ..

    # Test cloning from a server remote
    run dolt sql -q "call dolt_clone('http://localhost:50051/test-org/test-repo');"
    [ "$status" -eq 0 ]
    run dolt sql -q "use test_repo; show tables;"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test_table" ]] || false
}

package main

// dump_courses_test.go — выгрузка встроенных курсов в JSON для мобильного актива:
//   DUMP_COURSES=1 go test -run TestDumpCourses -v .
import (
	"encoding/json"
	"os"
	"testing"
)

func TestDumpCourses(t *testing.T) {
	if os.Getenv("DUMP_COURSES") == "" {
		t.Skip("set DUMP_COURSES=1 to dump")
	}
	os.MkdirAll("mobile/assets", 0o755)
	data, err := json.MarshalIndent(builtinCourses(), "", " ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile("mobile/assets/courses.json", data, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Log("dumped")
}

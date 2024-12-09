data "local_file" "missing_file" {
  filename = "${path.module}/missing_file.bar"
}

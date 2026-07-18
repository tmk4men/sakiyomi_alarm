#!/usr/bin/env ruby
# ios/Runner/Sounds/*.caf を Runner ターゲット（Copy Bundle Resources）に追加する。
# Xcode の GUI 操作の代わりにこれをターミナルで1回実行すればよい。
#
# 使い方（Mac・プロジェクト直下で）:
#   ruby scripts/ios/add_sounds.rb
# xcodeproj gem が無ければ:  sudo gem install xcodeproj
#
# 冪等: 既に追加済みならスキップ。実行後は flutter build ipa で反映。

require "xcodeproj"

PROJECT = "ios/Runner.xcodeproj"
SOUNDS = %w[classic ring alarm]

abort("#{PROJECT} が見つかりません。プロジェクト直下で実行してください。") unless File.exist?(PROJECT)

project = Xcodeproj::Project.open(PROJECT)
target = project.targets.find { |t| t.name == "Runner" }
abort("Runner ターゲットが見つかりません。") unless target

runner_group = project.main_group["Runner"] || project.main_group
sounds_group = runner_group["Sounds"] || runner_group.new_group("Sounds", "Sounds")

added = 0
SOUNDS.each do |name|
  fname = "#{name}.caf"
  path = "ios/Runner/Sounds/#{fname}"
  unless File.exist?(path)
    puts "  ⚠ #{path} が無いのでスキップ"
    next
  end

  # 既にリソースに入っていればスキップ（冪等）。
  already = target.resources_build_phase.files.any? do |bf|
    bf.file_ref && bf.file_ref.display_name == fname
  end
  if already
    puts "  ✓ 既に追加済み: #{fname}"
    next
  end

  ref = sounds_group.files.find { |f| f.display_name == fname } || sounds_group.new_reference(fname)
  target.resources_build_phase.add_file_reference(ref, true)
  puts "  ✅ 追加: #{fname}"
  added += 1
end

project.save
puts added > 0 ? "\n完了（#{added}件追加）。flutter build ipa で反映してください。" : "\n変更なし（すべて追加済み）。"

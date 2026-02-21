//
//  ComposeBarView.swift
//  EssayPublisher
//
//  底部输入栏：iOS 26 Liquid Glass 效果 + 双行布局

import SwiftUI
import PhotosUI

struct ComposeBarView: View {
    @ObservedObject var vm: ComposeViewModel
    var isFocused: FocusState<Bool>.Binding
    @State private var showCamera = false

    var body: some View {
        VStack(spacing: 0) {
            // 已选图片预览
            if !vm.attachedImages.isEmpty {
                imagePreviewRow
            }

            // 输入栏卡片
            inputCard
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
    }

    // MARK: - 输入卡片

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 文本输入
            TextField("", text: $vm.text, axis: .vertical)
                .lineLimit(1...6)
                .font(.system(size: 17))
                .foregroundStyle(Theme.textPrimary)
                .focused(isFocused)
                .tint(Theme.textPrimary)

            // 底部按钮行
            HStack(spacing: 0) {
                PhotosPicker(
                    selection: $vm.selectedItems,
                    maxSelectionCount: 9,
                    matching: .images
                ) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 36, height: 36)
                        .offset(x: -4)
                }
                .onChange(of: vm.selectedItems) {
                    vm.loadSelectedImages()
                }

                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 36, height: 36)
                }
                .fullScreenCover(isPresented: $showCamera) {
                    CameraView { image in
                        vm.addCameraImage(image)
                    }
                    .ignoresSafeArea()
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isFocused.wrappedValue = false
                    }
                    vm.publish()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(vm.canPublish ? .white : Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(vm.canPublish ? Theme.accent : Color.clear)
                        .clipShape(Circle())
                        .overlay {
                            if !vm.canPublish {
                                Circle().stroke(Theme.textSecondary.opacity(0.3), lineWidth: 1)
                            }
                        }
                }
                .disabled(!vm.canPublish)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .glassCard()
    }

    // MARK: - 已选图片预览行

    private var imagePreviewRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(vm.attachedImages.enumerated()), id: \.element.id) { index, img in
                    ZStack(alignment: .topTrailing) {
                        if let thumb = img.image {
                            Image(uiImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.surfaceLight)
                                .frame(width: 64, height: 64)
                        }

                        Button {
                            vm.removeImage(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, Theme.surfaceLight)
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Liquid Glass 卡片修饰器

extension View {
    @ViewBuilder
    func glassCard() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(in: .rect(cornerRadius: 22))
        } else {
            self.background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

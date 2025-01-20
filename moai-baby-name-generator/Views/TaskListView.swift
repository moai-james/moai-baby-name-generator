import SwiftUI

struct TaskListView: View {
    @ObservedObject private var taskManager = TaskManager.shared
    @State private var showingClaimAlert = false
    @State private var selectedMission: MissionItem?
    
    var body: some View {
        List(taskManager.missions) { mission in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mission.title)
                        .font(.custom("NotoSansTC-Regular", size: 16))
                        .foregroundColor(.customText)
                    
                    Text(mission.description)
                        .font(.custom("NotoSansTC-Regular", size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if mission.isRewardClaimed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if mission.isCompleted {
                    Text("領取")
                        .font(.custom("NotoSansTC-Regular", size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.customAccent)
                        .cornerRadius(12)
                } else {
                    Text("+\(mission.rewardUses)")
                        .font(.custom("NotoSansTC-Regular", size: 14))
                        .foregroundColor(.customAccent)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                if mission.isCompleted && !mission.isRewardClaimed {
                    selectedMission = mission
                    showingClaimAlert = true
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("任務中心")
        .alert("領取獎勵", isPresented: $showingClaimAlert) {
            Button("取消", role: .cancel) { }
            Button("確定") {
                if let mission = selectedMission {
                    Task {
                        await taskManager.claimReward(mission.type)
                    }
                }
            }
        } message: {
            if let mission = selectedMission {
                Text("確定要領取 \(mission.rewardUses) 次使用機會嗎？")
            }
        }
    }
} 